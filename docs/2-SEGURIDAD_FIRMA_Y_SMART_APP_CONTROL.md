# Firma Digital, Seguridad de Windows y Smart App Control

## 1. Por qué Windows bloqueó anteriormente el archivo descargado
El mensaje:
> *«Una directiva de Control de aplicaciones bloqueó este archivo porque no pudimos comprobar su publicador para confirmar que era seguro ejecutarlo»*

se produce cuando **Smart App Control (Control Inteligente de Aplicaciones)** de Windows 11 analiza un archivo `.exe` descargado de Internet (con la etiqueta NTFS `Zone.Identifier`) que no cuenta con reputación global en la nube de Microsoft (*Intelligent Security Graph*) ni está firmado digitalmente por una Autoridad de Certificación (CA) pública reconocida.

## 2. Por qué el sistema incluido en este ZIP evita ese bloqueo al crearse localmente
Cuando descargas un `.exe` ya compilado dentro de un `.zip` desde un navegador web, Windows etiqueta ese `.exe` como *procedente de Internet* (`Mark of the Web`).
En cambio, al ejecutar `ABRIR_GAMELAUNCHER.bat`:
1. Es el propio compilador nativo de tu Windows (`C:\Windows\Microsoft.NET\Framework644.0.30319\csc.exe`, firmado digitalmente por Microsoft) quien construye localmente `GameLauncher.exe` en tu disco duro a partir del código fuente limpio.
2. El archivo `GameLauncher.exe` resultante nace localmente en tu máquina sin etiqueta de descarga externa (`Zone.Identifier`).

## 3. Diferencia entre Compilar, Firmar Digitalmente y Obtener Reputación
- **Compilar:** Transforma el código fuente C# en el archivo binario `GameLauncher.exe`. No añade identidad de publicador.
- **Firmar Digitalmente (Authenticode):** Aplica un sello criptográfico SHA-256 con un certificado emitido por una Autoridad Certificadora (CA) pública (como Microsoft Artifact Signing, DigiCert o Sectigo) más un sello de tiempo RFC 3161. Garantiza quién es el editor y que el ejecutable no ha sido alterado.
- **Reputación de Aplicación:** Es la puntuación de confianza que el sistema *Intelligent Security Graph* de Microsoft asigna en la nube a un archivo o certificado a lo largo del tiempo.

## 4. Cómo firmar `GameLauncher.exe` para distribuirlo a terceros
Si deseas enviar `GameLauncher.exe` ya compilado o su instalador a otros ordenadores con *Smart App Control* activo:
1. Obtén un certificado de firma de código de una CA reconocida (por ejemplo, **Microsoft Artifact Signing**, DigiCert o Sectigo). **Nota:** Un certificado autofirmado no sirve porque no pertenece a una CA raíz de confianza pública.
2. Abre PowerShell en la carpeta `scripts/` y ejecuta:
   ```powershell
   .-Firmar-Binarios.ps1 -CertThumbprint "HUELLA_SHA1_DE_TU_CERTIFICADO"
   ```
3. Verifica la firma ejecutando:
   ```powershell
   .-Verificar-Firma-y-SmartAppControl.ps1
   ```
