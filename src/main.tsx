import ReactDOM from 'react-dom/client'
import { StrictMode } from 'react'
import App from './App'
import AuthGate from './AuthGate'
import './styles.css'
ReactDOM.createRoot(document.getElementById('root')!).render(<StrictMode><AuthGate><App /></AuthGate></StrictMode>)
