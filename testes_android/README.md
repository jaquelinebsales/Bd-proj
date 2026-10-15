# Testes no Android

QA automático do app no emulador do Android Studio ou num celular pelo cabo, tela por tela e botão por botão, contra o servidor real. O resultado entra na planilha da auditoria (`documentacao/auditoria/auditoria_gasprice.xlsx`, aba **Android (emulador)**), com uma captura de tela por caso.

## Antes da primeira vez

1. **Servidor no ar.** A VM `servidor-michael` precisa estar ligada (confira com `tailscale status`).
2. **Um aparelho.** Escolha um dos dois:
   - **Emulador:** o Windows precisa do hipervisor. No PowerShell **como administrador**, rode o comando abaixo e reinicie o PC. O script liga o emulador `Medium_Phone` sozinho.
     ```powershell
     Enable-WindowsOptionalFeature -Online -FeatureName HypervisorPlatform -All
     ```
   - **Celular:** em Configurações → Sobre o telefone, toque 7 vezes em "Número da versão". Depois, em Opções do desenvolvedor, ligue a **Depuração USB** e conecte o cabo. Aceite o pedido de confiança no celular.
3. O `.env` da raiz precisa ter `SUPABASE_SECRET_KEY`: ela cria e apaga a conta de teste.

## Rodar

Na raiz do projeto:

```powershell
py -3.12 testes_android/executar.py
```

Leva uns 15 a 25 minutos, quase tudo no primeiro build. No fim:

- a planilha fica atualizada (feche o Excel antes);
- as capturas ficam em `documentacao/auditoria/evidencias/android_emulador/`;
- o APK de testes fica em `testes_android/apk/` (fora do git), pronto para instalar no celular;
- o log completo fica em `testes_android/saida/flutter_test.log`.

Outros usos:

| Comando | O que faz |
|---|---|
| `executar.py --so-apk` | Só gera o APK de testes |
| `executar.py --sem-apk --sem-planilha` | Só roda os testes |
| `executar.py --dispositivo emulator-5554` | Escolhe o aparelho quando há mais de um |
| `executar.py --url http://servidor-michael:8000` | Usa o endereço da Tailscale em vez do público |
| `executar.py --limpar` | Apaga contas de teste que sobraram de uma execução interrompida |

## O que é testado

O fluxo segue o caminho de uma pessoa nova: boas-vindas, barra inferior, mapa (carga, toque no pino, folha que expande, combustível com vários marcados, raio, localização), busca (texto, ordenação conferida nos cartões, filtros conferidos nos cartões), página do posto (favoritar, contribuições, histórico, avaliações, como chegar, pedidos de login), cadastro (validações, gênero, data de nascimento, termos), entrar (validações, senha errada, recuperar senha), perfil (nome, pontos, ranking, alterar dados, alterar senha, notificações, sobre), avaliação publicada e apagada, favoritos na conta, sair, entrar com a senha nova e excluir a conta.

Também reprova o caso se o Flutter registrar erro durante ele (estouro de layout, exceção).

## Conta de teste e dados reais

- Cada execução cria `qa.<data e hora>@auditoria.gasprice.test`, já confirmada e com o nome "Qa Teste". O domínio `.test` não recebe e-mail.
- No fim, a própria suíte exclui a conta pelo botão do app. O script confere no servidor e apaga se tiver sobrado.
- Uma avaliação "Teste automatizado de QA, pode ignorar." fica publicada por alguns segundos num posto real e é apagada pelo app.
- **Não há envio de preço nem de posição de posto**: esses dados ficariam no histórico real mesmo depois de apagar a conta. A câmera com painel real, o link de e-mail e as notificações continuam no roteiro manual (aba **Android (manual)** da planilha).
