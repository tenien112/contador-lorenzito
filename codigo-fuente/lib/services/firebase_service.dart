import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';

class FirebaseService {
  FirebaseAuth get _auth => FirebaseAuth.instance;
  FirebaseFirestore get _db => FirebaseFirestore.instance;

  // Stream of auth state changes
  Stream<User?> get userSnapshot => _auth.authStateChanges();

  // Stream of VIP status
  Stream<bool> isUserVip() {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return Stream.value(false);

    return _db.collection('users').doc(currentUser.uid).snapshots().map((doc) {
      if (doc.exists) {
        return doc.data()?['isVip'] ?? false;
      }
      return false;
    });
  }

  // Update VIP status (for testing or after payment)
  Future<void> updateVipStatus(bool status) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    await _db.collection('users').doc(currentUser.uid).set({
      'isVip': status,
    }, SetOptions(merge: true));
  }

  // Anonymous Sign In
  Future<UserCredential?> signInAnonymously() async {
    try {
      return await _auth.signInAnonymously();
    } catch (e) {
      debugPrint("Error signing in anonymously: $e");
      return null;
    }
  }

  // Sync Local SharedPreferences to Firestore
  Future<void> syncLocalToCloud() async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final String? sessionsJson = prefs.getString('saved_sessions');

      if (sessionsJson != null) {
        final List<dynamic> localSessions = json.decode(sessionsJson);

        // Use a batch to upload everything
        final batch = _db.batch();
        final userDoc = _db.collection('users').doc(currentUser.uid);

        for (var session in localSessions) {
          final sessionMap = Map<String, dynamic>.from(session);
          final startTime = sessionMap['startTime'];
          if (startTime != null) {
            final sessionDoc = userDoc.collection('sessions').doc(startTime);
            batch.set(sessionDoc, sessionMap, SetOptions(merge: true));
          }
        }

        await batch.commit();
        debugPrint("Synced ${localSessions.length} sessions to cloud.");
      }
    } catch (e) {
      debugPrint("Error syncing to cloud: $e");
    }
  }

  // Sync Cloud Firestore to Local SharedPreferences
  Future<void> syncCloudToLocal() async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    try {
      final querySnapshot = await _db
          .collection('users')
          .doc(currentUser.uid)
          .collection('sessions')
          .orderBy('startTime', descending: true)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        final List<Map<String, dynamic>> cloudSessions =
            querySnapshot.docs.map((doc) => doc.data()).toList();

        final prefs = await SharedPreferences.getInstance();
        final String? localSessionsJson = prefs.getString('saved_sessions');

        List<Map<String, dynamic>> mergedSessions = [];
        if (localSessionsJson != null) {
          mergedSessions =
              List<Map<String, dynamic>>.from(json.decode(localSessionsJson));
        }

        // Simple merge logic: if startTime is new, add it
        for (var cloudSession in cloudSessions) {
          final exists = mergedSessions
              .any((s) => s['startTime'] == cloudSession['startTime']);
          if (!exists) {
            mergedSessions.add(cloudSession);
          }
        }

        // Sort by date descending
        mergedSessions.sort((a, b) =>
            (b['startTime'] as String).compareTo(a['startTime'] as String));

        await prefs.setString('saved_sessions', json.encode(mergedSessions));
        debugPrint("Synced sessions from cloud to local.");
      }
    } catch (e) {
      debugPrint("Error syncing from cloud: $e");
    }
  }

  Future<void> signOut() async {
    await _auth.signOut();
  }
}
