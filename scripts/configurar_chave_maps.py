"""
Copia a GOOGLE_MAPS_API_KEY do .env para os arquivos que o app lê ao ser compilado:
  app/android/local.properties     (linha MAPS_API_KEY=...)
  app/ios/Flutter/Secrets.xcconfig (linha MAPS_API_KEY = ...)
Os dois arquivos ficam fora do Git. A chave nunca é exibida.

Uso: python scripts/configurar_chave_maps.py
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

RAIZ = Path(__file__).resolve().parents[1]


def ler_chave() -> str:
    env = RAIZ / ".env"
    if not env.exists():
        sys.exit("Arquivo .env não encontrado na raiz do projeto.")
    for linha in env.read_text(encoding="utf-8-sig").splitlines():
        if re.match(r"\s*GOOGLE_MAPS_API_KEY\s*=", linha):
            valor = linha.split("=", 1)[1].strip().strip('"').strip("'")
            if valor:
                return valor
    sys.exit("Preencha GOOGLE_MAPS_API_KEY no .env e salve o arquivo (Ctrl+S).")


def gravar(arquivo: Path, padrao: str, linha_nova: str) -> None:
    texto = arquivo.read_text(encoding="utf-8") if arquivo.exists() else ""
    if re.search(padrao, texto, flags=re.M):
        texto = re.sub(padrao, linha_nova.replace("\\", "\\\\"), texto, flags=re.M)
    else:
        texto = texto.rstrip("\n") + ("\n" if texto else "") + linha_nova + "\n"
    arquivo.write_text(texto, encoding="utf-8")


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    chave = ler_chave()
    if not chave.startswith("AIza") or len(chave) < 35:
        print("Aviso: a chave não tem o formato usual do Google (começa com AIza e tem 39 caracteres). Confira se copiou inteira.")
    gravar(RAIZ / "app" / "android" / "local.properties", r"^MAPS_API_KEY=.*$", f"MAPS_API_KEY={chave}")
    gravar(RAIZ / "app" / "ios" / "Flutter" / "Secrets.xcconfig", r"^MAPS_API_KEY\s*=.*$", f"MAPS_API_KEY = {chave}")
    print("Chave gravada em app/android/local.properties e app/ios/Flutter/Secrets.xcconfig (fora do Git).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
