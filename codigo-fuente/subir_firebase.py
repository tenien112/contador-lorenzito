import subprocess
import os
import re
import sys

def run(command, msg):
    print(f"\n>> {msg}...")
    # Usamos shell=True y dejamos que el sistema maneje el encoding de salida
    result = subprocess.run(command, shell=True)
    if result.returncode != 0:
        print(f"ERROR: Fallo en el paso: {msg}")
        sys.exit(1)

def increment_version():
    print("\n>> Incrementando version en pubspec.yaml...")
    file_path = "pubspec.yaml"
    
    if not os.path.exists(file_path):
        print("Error: No se encontro pubspec.yaml")
        return

    # LEER COMO BINARIO (rb) para evitar errores de charmap/unicode
    with open(file_path, 'rb') as f:
        content_binary = f.read()
    
    # Convertimos a string ignorando errores de caracteres extraños
    content = content_binary.decode('utf-8', errors='ignore')

    match = re.search(r"version: (\d+\.\d+\.\d+)\+(\d+)", content)
    if match:
        version_name = match.group(1)
        build_number = int(match.group(2)) + 1
        new_version = f"version: {version_name}+{build_number}"
        
        new_content = re.sub(r"version: \d+\.\d+\.\d+\+\d+", new_version, content)
        
        # ESCRIBIR COMO BINARIO para asegurar compatibilidad total
        with open(file_path, 'wb') as f:
            f.write(new_content.encode('utf-8'))
        print(f"Nueva version establecida: {version_name}+{build_number}")
    else:
        print("No se pudo encontrar el formato de version.")

def deploy_to_firebase():
    run("flutter clean", "Limpiando proyecto")
    run("flutter pub get", "Actualizando dependencias")
    increment_version()
    run("flutter build web --release", "Compilando Flutter Web")
    run("firebase deploy --only hosting", "Subiendo a Firebase")
    print("\n PROCESO COMPLETADO EXITOSAMENTE")

if __name__ == "__main__":
    deploy_to_firebase()

    