"""
QA do app no Android (emulador do Android Studio ou celular pelo cabo), contra o servidor real.

O que faz, na ordem:
  1. confere se o servidor responde e se há um aparelho no adb (liga o emulador se não houver);
  2. cria a conta de teste qa.<data>@auditoria.gasprice.test, já confirmada (o domínio .test não recebe e-mail);
  3. põe o GPS do emulador em São Paulo e roda app/integration_test/qa_app_test.dart no aparelho;
  4. atende os pedidos da suíte: permissões, capturas de tela (adb screencap) e trazer o app de volta;
  5. apaga a conta de teste (se a suíte não apagou pelo app) e grava os resultados para a planilha;
  6. gera o APK de testes em testes_android/apk/ e atualiza documentacao/auditoria/auditoria_gasprice.xlsx.

Uso (na raiz do projeto):
  py -3.12 testes_android/executar.py              QA completo + APK + planilha
  py -3.12 testes_android/executar.py --so-apk     só gera o APK de testes
  py -3.12 testes_android/executar.py --limpar     apaga contas de teste que tenham sobrado
Opções: --dispositivo ID, --sem-apk, --sem-planilha, --url URL (outro endereço do servidor, ex.: http://servidor-michael:8000)
"""
from __future__ import annotations

import argparse
import json
import os
import secrets
import shutil
import subprocess
import sys
import threading
import time
from datetime import datetime
from pathlib import Path

RAIZ = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(RAIZ / "scripts" / "auditoria"))
import comum  # noqa: E402

PASTA = Path(__file__).resolve().parent
APP = RAIZ / "app"
SAIDA = PASTA / "saida"
APKS = PASTA / "apk"
CAPTURAS = comum.EVIDENCIAS / "android_emulador"
PACOTE = "br.com.gasprice.gasprice"
DOMINIO = "auditoria.gasprice.test"
NOME = "Qa Teste"
SAO_PAULO = (-46.6559, -23.5614)  # lon, lat (Av. Paulista)
PERMISSOES = ["ACCESS_FINE_LOCATION", "ACCESS_COARSE_LOCATION", "POST_NOTIFICATIONS", "CAMERA"]

SDK = Path(os.environ.get("ANDROID_HOME") or Path(os.environ["LOCALAPPDATA"]) / "Android" / "Sdk")
ADB = SDK / "platform-tools" / "adb.exe"
EMULADOR = SDK / "emulator" / "emulator.exe"
FLUTTER = Path(os.environ.get("FLUTTER", Path.home() / "dev-tools" / "flutter" / "bin" / "flutter.bat"))
JDK = Path(os.environ.get("JAVA_HOME") or Path(os.environ.get("ProgramFiles", r"C:\Program Files")) / "Android" / "Android Studio" / "jbr")


def ambiente() -> dict:
    env = dict(os.environ, ANDROID_HOME=str(SDK), JAVA_HOME=str(JDK))
    env["PATH"] = os.pathsep.join([str(SDK / "platform-tools"), str(FLUTTER.parent), env.get("PATH", "")])
    return env


def adb(*args: str, dispositivo: str | None = None, saida_binaria: bool = False, timeout: int = 60):
    cmd = [str(ADB)] + (["-s", dispositivo] if dispositivo else []) + list(args)
    r = subprocess.run(cmd, capture_output=True, timeout=timeout)
    return r.stdout if saida_binaria else r.stdout.decode("utf-8", "replace").strip()


# ------------------------------------------------------------------ servidor e conta de teste
def checar_servidor() -> str | None:
    r = comum.http("GET", "/auth/v1/health", timeout=15)
    if r.status != 200:
        return f"Servidor {comum.URL} não respondeu ({comum.resumo(r, 160)})."
    if not comum.SECRETA:
        return "SUPABASE_SECRET_KEY ausente no .env: sem ela não dá para criar a conta de teste."
    return None


def senha_forte() -> str:
    return f"Qa!{secrets.token_hex(4)}A{secrets.randbelow(90) + 10}"


def criar_conta() -> dict:
    email = f"qa.{datetime.now():%Y%m%d%H%M%S}@{DOMINIO}"
    senha, nova = senha_forte(), senha_forte()
    r = comum.http("POST", "/auth/v1/admin/users", {"email": email, "password": senha, "email_confirm": True,
                                                    "user_metadata": {"nome": NOME}}, chave=comum.SECRETA)
    if r.status not in (200, 201) or not isinstance(r.corpo, dict):
        raise SystemExit(f"Não consegui criar a conta de teste: {comum.resumo(r)}")
    return {"id": r.corpo["id"], "email": email, "senha": senha, "nova": nova}


def contas_de_teste() -> list[dict]:
    r = comum.http("GET", "/auth/v1/admin/users?per_page=1000", chave=comum.SECRETA)
    usuarios = (r.corpo or {}).get("users", []) if isinstance(r.corpo, dict) else []
    return [u for u in usuarios if str(u.get("email", "")).startswith("qa.") and u["email"].endswith("@" + DOMINIO)]


def apagar_conta(uid: str) -> int:
    return comum.http("DELETE", f"/auth/v1/admin/users/{uid}", chave=comum.SECRETA).status


def conta_existe(uid: str) -> bool:
    return comum.http("GET", f"/auth/v1/admin/users/{uid}", chave=comum.SECRETA).status == 200


# ------------------------------------------------------------------ aparelho
def escolher_dispositivo(pedido: str | None) -> tuple[str, bool]:
    def lista() -> list[str]:
        linhas = adb("devices").splitlines()[1:]
        return [l.split("\t")[0] for l in linhas if l.endswith("\tdevice")]

    disp = lista()
    if pedido:
        if pedido not in disp:
            raise SystemExit(f"Aparelho {pedido} não está no adb. Conectados: {disp or 'nenhum'}")
        return pedido, pedido.startswith("emulator-")
    if disp:
        return disp[0], disp[0].startswith("emulator-")
    avds = subprocess.run([str(EMULADOR), "-list-avds"], capture_output=True, text=True).stdout.split()
    if not avds:
        raise SystemExit("Nenhum aparelho no adb e nenhum emulador criado no Android Studio.")
    print(f"Ligando o emulador {avds[0]}…")
    subprocess.Popen([str(EMULADOR), "-avd", avds[0], "-no-snapshot-save", "-no-boot-anim"],
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    fim = time.time() + 240
    while time.time() < fim:
        time.sleep(5)
        disp = lista()
        if disp and adb("shell", "getprop", "sys.boot_completed", dispositivo=disp[0]) == "1":
            return disp[0], True
    raise SystemExit(
        "O emulador não ligou. Se o Android Studio avisar que falta o hypervisor, rode no PowerShell como administrador:\n"
        "  Enable-WindowsOptionalFeature -Online -FeatureName HypervisorPlatform -All\n"
        "e reinicie o computador. Ou conecte um celular com a Depuração USB ligada.")


def escrever_config() -> Path:
    SAIDA.mkdir(parents=True, exist_ok=True)
    arq = SAIDA / "app.json"
    arq.write_text(json.dumps({
        "SUPABASE_URL": comum.URL,
        "SUPABASE_PUBLISHABLE_KEY": comum.PUB,
        "SUPABASE_SCHEMA": comum.ENV.get("SUPABASE_SCHEMA", "public").strip() or "public",
    }, indent=1), encoding="utf-8")
    return arq


# ------------------------------------------------------------------ execução da suíte
class Execucao:
    def __init__(self, dispositivo: str):
        self.disp = dispositivo
        self.resultados: list[dict] = []
        self.fim: int | None = None
        CAPTURAS.mkdir(parents=True, exist_ok=True)

    def _adb(self, *args: str, **kw):
        return adb(*args, dispositivo=self.disp, **kw)

    def atender(self, linha: str) -> None:
        if "QA_RESULTADO:" in linha:
            self.resultados.append(json.loads(linha.split("QA_RESULTADO:", 1)[1]))
            r = self.resultados[-1]
            marca = {"PASS": "ok    ", "FAIL": "FALHOU", "NOT TESTED": "NÃO   "}.get(r["status"], r["status"])
            print(f"  {marca} {r['id']} {r['cenario'][:100]}", flush=True)
        elif "QA_CAPTURA:" in linha:
            nome = linha.split("QA_CAPTURA:", 1)[1].strip()
            png = self._adb("exec-out", "screencap", "-p", saida_binaria=True)
            (CAPTURAS / f"{nome}.png").write_bytes(png)
        elif "QA_ADB:" in linha:
            pedido = linha.split("QA_ADB:", 1)[1].strip()
            if pedido == "conceder_permissoes":
                for p in PERMISSOES:
                    self._adb("shell", "pm", "grant", PACOTE, f"android.permission.{p}")
            elif pedido.startswith("voltar_app_em:"):
                atraso = float(pedido.split(":", 1)[1])

                def voltar():
                    time.sleep(atraso)
                    self._adb("shell", "monkey", "-p", PACOTE, "-c", "android.intent.category.LAUNCHER", "1")
                threading.Thread(target=voltar, daemon=True).start()
            elif pedido.startswith("tap:"):
                _, x, y = pedido.split(":")
                self._adb("shell", "input", "tap", x, y)
        elif "QA_FIM:" in linha:
            self.fim = int(linha.split("QA_FIM:", 1)[1].strip() or 0)

    def rodar(self, config: Path, conta: dict) -> int:
        cmd = [str(FLUTTER), "test", "integration_test/qa_app_test.dart", "-d", self.disp,
               f"--dart-define-from-file={config}",
               f"--dart-define=QA_EMAIL={conta['email']}", f"--dart-define=QA_SENHA={conta['senha']}",
               f"--dart-define=QA_SENHA_NOVA={conta['nova']}", f"--dart-define=QA_NOME={NOME}"]
        log = (SAIDA / "flutter_test.log").open("w", encoding="utf-8")
        proc = subprocess.Popen(cmd, cwd=APP, env=ambiente(), stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                text=True, encoding="utf-8", errors="replace", bufsize=1)
        for linha in proc.stdout:
            log.write(comum.mascarar(linha))
            if "QA_" in linha:
                self.atender(linha)
            elif any(p in linha for p in ("Running Gradle", "Installing", "error", "Error", "Exception", "FAILED", "passed", "failed")):
                print("  │ " + comum.mascarar(linha.rstrip())[:200], flush=True)
        log.close()
        return proc.wait()


def gravar(resultados: list[dict], extras: list[dict]) -> Path:
    suite = comum.Suite("android_emulador", "EMU")
    for r in resultados + extras:
        cap = r.get("captura")
        suite.add(id=r["id"], aba="Android (emulador)", modulo=r["modulo"], tela=r["tela"], tipo=r["tipo"],
                  cenario=r["cenario"], precondicoes=r.get("precondicoes", "-"), passos=r["passos"],
                  entrada=r.get("entrada", "-"), esperado=r["esperado"], obtido=r["obtido"], status=r["status"],
                  severidade=r.get("severidade", comum.MEDIA), duracao_ms=r.get("duracao_ms"),
                  evidencia=f"evidencias/android_emulador/{cap}.png" if cap else "resultados/android_emulador.json")
    suite.salvar()
    return comum.RESULTADOS / "android_emulador.json"


def gerar_apk(config: Path) -> Path | None:
    print("Gerando o APK de testes (release, apontando para o servidor real)…", flush=True)
    r = subprocess.run([str(FLUTTER), "build", "apk", "--release", f"--dart-define-from-file={config}"],
                       cwd=APP, env=ambiente(), capture_output=True, text=True, encoding="utf-8", errors="replace")
    origem = APP / "build" / "app" / "outputs" / "flutter-apk" / "app-release.apk"
    if r.returncode != 0 or not origem.exists():
        print("Falhou ao gerar o APK:\n" + comum.mascarar(r.stdout[-3000:] + r.stderr[-3000:]))
        return None
    APKS.mkdir(parents=True, exist_ok=True)
    destino = APKS / f"gasprice-teste-{datetime.now():%Y%m%d-%H%M}.apk"
    shutil.copy2(origem, destino)
    print(f"APK: {destino} ({destino.stat().st_size / 1e6:.1f} MB)")
    return destino


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--dispositivo")
    ap.add_argument("--so-apk", action="store_true")
    ap.add_argument("--sem-apk", action="store_true")
    ap.add_argument("--sem-planilha", action="store_true")
    ap.add_argument("--limpar", action="store_true")
    ap.add_argument("--url")
    a = ap.parse_args()
    if a.url:
        comum.URL = a.url.rstrip("/")

    problema = checar_servidor()
    if problema:
        print(problema + "\nSe a VM estiver ligada, teste também --url http://servidor-michael:8000 (pela Tailscale).")
        return 2
    if a.limpar:
        sobras = contas_de_teste()
        for u in sobras:
            print(f"apagando {u['email']}: HTTP {apagar_conta(u['id'])}")
        print(f"{len(sobras)} conta(s) de teste apagada(s)")
        return 0
    config = escrever_config()
    if a.so_apk:
        return 0 if gerar_apk(config) else 1

    disp, emulador = escolher_dispositivo(a.dispositivo)
    print(f"Aparelho: {disp} ({'emulador' if emulador else 'celular'}); servidor: {comum.URL}")
    if emulador:
        adb("emu", "geo", "fix", str(SAO_PAULO[0]), str(SAO_PAULO[1]), dispositivo=disp)
    for p in CAPTURAS.glob("*.png"):
        p.unlink()

    conta = criar_conta()
    print(f"Conta de teste: {conta['email']}")
    ex = Execucao(disp)
    extras: list[dict] = []
    codigo = 1
    try:
        codigo = ex.rodar(config, conta)
    finally:
        apagada_pelo_app = not conta_existe(conta["id"])
        if not apagada_pelo_app:
            apagar_conta(conta["id"])
        extras.append(dict(
            id=f"EMU-{len(ex.resultados) + 1:03d}", modulo="Conta", tela="Servidor (Supabase Auth)", tipo="Integração · exclusão",
            cenario="Excluir conta pelo app remove o usuário do servidor",
            precondicoes="Suíte chegou ao fim", passos="Depois da suíte, consultar o usuário de teste pela API de administração",
            esperado="Usuário não existe mais (HTTP 404)", severidade=comum.ALTA,
            status=comum.PASS if apagada_pelo_app else comum.FAIL,
            obtido="Usuário já não existia: a função excluir-conta apagou" if apagada_pelo_app
            else "Usuário ainda existia; apagado pelo executar.py"))
        if ex.fim is None:
            extras.append(dict(
                id=f"EMU-{len(ex.resultados) + 2:03d}", modulo="Suíte", tela="-", tipo="Execução",
                cenario="Suíte de QA chega ao fim sem travar", passos="flutter test integration_test/qa_app_test.dart",
                esperado="Marcador QA_FIM no fim da execução", severidade=comum.ALTA, status=comum.FAIL,
                obtido=f"Parou depois de {len(ex.resultados)} casos (código {codigo}); ver testes_android/saida/flutter_test.log"))

    gravar(ex.resultados, extras)
    if not a.sem_apk:
        gerar_apk(config)
    if not a.sem_planilha:
        subprocess.run([sys.executable, str(RAIZ / "scripts" / "auditoria" / "gerar_planilha.py")], cwd=RAIZ)
    falhas = sum(r["status"] == comum.FAIL for r in ex.resultados + extras)
    print(f"\n{len(ex.resultados) + len(extras)} casos, {falhas} falha(s). Capturas em {CAPTURAS}")
    return 0 if falhas == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
