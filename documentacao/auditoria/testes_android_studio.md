# Testar o gasprice no Android Studio

Os 30 casos da aba **Android (manual)** da planilha `auditoria_gasprice.xlsx` só rodam num celular Android ou no emulador. Este guia prepara o ambiente e mostra como executar e registrar cada caso.

## 1. Instalar o Android Studio

1. Baixe em https://developer.android.com/studio e instale com as opções padrão. Deixe marcados **Android SDK**, **Android SDK Platform-Tools** e **Android Virtual Device**.
2. Na primeira abertura, escolha **Standard** e aceite as licenças. O download do SDK leva alguns minutos.
3. Em **More Actions → SDK Manager**:
   - Aba **SDK Platforms**: marque **Android 15 (API 35)**.
   - Aba **SDK Tools**: marque **Android SDK Command-line Tools (latest)**.
   - Clique em **Apply**.

## 2. Ligar o Flutter ao Android Studio

No PowerShell:

```powershell
$env:Path = "C:\Users\michael\dev-tools\flutter\bin;C:\Users\michael\dev-tools\git\cmd;$env:Path"
flutter config --android-sdk "$env:LOCALAPPDATA\Android\Sdk"
flutter doctor --android-licenses   # responda y a todas
flutter doctor                      # Android toolchain deve aparecer com ✓
```

No Android Studio, abra **Plugins**, instale **Flutter** (ele instala o Dart junto) e reinicie. Em **Settings → Languages & Frameworks → Flutter**, informe o SDK: `C:\Users\michael\dev-tools\flutter`.

## 3. Abrir o projeto e configurar a conexão

1. **File → Open** e escolha a pasta `C:\Users\michael\Desktop\gasprice\app`.
2. Copie `app\config\app.example.json` para `app\config\app.json` e preencha com os valores do `.env`:
   - `SUPABASE_URL`
   - `SUPABASE_PUBLISHABLE_KEY` (a chave `sb_publishable_...`, nunca a secreta)

   O arquivo `app.json` fica fora do Git.
3. **Run → Edit Configurations → main.dart**. Em **Additional run args**, coloque:

   ```
   --dart-define-from-file=config/app.json
   ```

## 4. Escolher onde rodar

**Celular de verdade (recomendado para câmera e GPS):**
1. No celular: **Configurações → Sobre o telefone**, toque 7 vezes em **Número da versão**. Depois, em **Opções do desenvolvedor**, ligue **Depuração USB**.
2. Ligue o cabo e aceite o aviso **Permitir depuração USB**.
3. O celular aparece na lista de aparelhos do Android Studio.

**Emulador:**
1. **Device Manager → Create Device → Pixel 7 → imagem API 35 com Google Play** (precisa do Play para o Google Maps do "Como chegar").
2. **GPS:** nos três pontinhos do emulador, abra **Location**, procure um endereço (por exemplo, um posto em Fortaleza) e clique em **Set location**.
3. **Câmera:** em **Camera → Virtual scene images**, coloque a foto de um painel de preços na parede da cena virtual. Na câmera do app, ande até a parede para fotografar. Para a leitura do painel, o celular de verdade dá um resultado mais fiel.

## 5. Rodar

Escolha o aparelho e clique em ▶ **Run**. O primeiro build leva de 5 a 10 minutos. Em modo de depuração, um estouro de layout aparece como uma faixa amarela e preta na tela e como `RenderFlex overflowed` na aba **Run**.

Pelo terminal, o mesmo comando é:

```powershell
cd C:\Users\michael\Desktop\gasprice\app
flutter run --dart-define-from-file=config/app.json
```

## 6. Executar os casos e registrar

1. Abra `documentacao\auditoria\auditoria_gasprice.xlsx` na aba **Android (manual)**.
2. Para cada linha, siga **Pré-condições** e **Passos** e compare com o **Resultado Esperado**.
3. Escreva o que aconteceu em **Resultado Obtido** (coluna J, amarela) e escolha o **Status** na lista (coluna K): 🟢 PASS, 🔴 FAIL ou 🟡 BLOCKED. O Dashboard se atualiza sozinho.
4. Em falhas, guarde uma captura (no emulador: ícone de câmera na barra lateral) e anote o nome do arquivo em **Evidência**.

Prioridade: primeiro os casos de severidade **Crítica** (instalação, câmera, leitura do painel, privacidade da foto, confirmação por duas pessoas e e-mail de confirmação). Depois os de severidade **Alta**.

## 7. O que me mandar

- A planilha preenchida.
- As fotos de painel em que o leitor errou, com o que ele leu e o que deveria ter lido.
- O texto do erro da aba **Run** quando o app fechar sozinho.
