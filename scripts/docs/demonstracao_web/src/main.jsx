import { createRoot } from 'react-dom/client';
import '@fontsource/barlow/400.css';
import '@fontsource/barlow/500.css';
import '@fontsource/barlow/600.css';
import '@fontsource/ibm-plex-mono/400.css';
import './estilo.css';
import App from './App.jsx';

// O ícone vem do app (pasta app/ ao lado), que o Vite não conhece no build
const icone = document.createElement('link');
icone.rel = 'icon';
icone.type = 'image/png';
icone.href = 'app/favicon.png';
document.head.append(icone);

createRoot(document.getElementById('raiz')).render(<App />);
