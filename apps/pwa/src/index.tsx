import { render } from 'solid-js/web'
import { App } from './App.tsx'
import { registerServiceWorker } from './services/sw-register.ts'
import './styles/tokens.css'
import './styles/base.css'
import './styles/components.css'

const root = document.getElementById('root')
if (!root) throw new Error('Missing #root')

render(() => <App />, root)

registerServiceWorker()
