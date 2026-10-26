# Demonstração do GasPrice

Pasta gerada por `scripts/docs/gerar_demonstracao.py`. Não vai para o GitHub.

- `index.html` e `assets/`: a página da demonstração (aparelho em 3D que se abre de celular em tablet e painel ao vivo).
- `app/`: o app em Flutter web, no modo demonstração (dados fictícios, sem servidor).

## Publicar no portfólio

Copie a pasta inteira para o site, em qualquer caminho (por exemplo `/projetos/gasprice/`).
Ela só tem arquivos estáticos: serve em qualquer hospedagem (GitHub Pages, Netlify, Vercel, servidor próprio).

- Abra pelo endereço `.../index.html` ou `.../` servido pelo site. Aberto direto do disco (`file://`),
  o navegador bloqueia o app.
- Para testar no computador: `py -3 -m http.server 8000` dentro desta pasta e abra http://localhost:8000.
- O mapa usa os blocos do OpenFreeMap pela internet e precisa de WebGL no navegador.

Para gerar de novo depois de mudar o app: `py -3.12 scripts/docs/gerar_demonstracao.py`.
