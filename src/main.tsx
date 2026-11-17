import ReactDOM from 'react-dom/client'
import { StrictMode } from 'react'
import MultiTeamApp from './MultiTeamApp'
import './styles.css'
ReactDOM.createRoot(document.getElementById('root')!).render(<StrictMode><MultiTeamApp /></StrictMode>)

if ('serviceWorker' in navigator && import.meta.env.PROD) {
  window.addEventListener('load', () => { void navigator.serviceWorker.register('/sw.js') })
}
