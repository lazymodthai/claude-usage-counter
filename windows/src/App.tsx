import { useEffect } from 'react'
import { useStore } from './store'
import { Header } from './components/Header'
import { ProviderSection } from './components/ProviderSection'
import { Footer } from './components/Footer'
import { Settings } from './components/Settings'
import { CompactView } from './components/CompactView'
import { ALL_PROVIDERS } from './types'
import './App.css'

const REFRESH_INTERVAL_MS = 60_000

export function App() {
  const opacity = useStore(s => s.opacity)
  const compact = useStore(s => s.compact)
  const showSettings = useStore(s => s.showSettings)
  const refreshAll = useStore(s => s.refreshAll)
  const initWindow = useStore(s => s.initWindow)

  useEffect(() => {
    initWindow()
    refreshAll()
    const id = setInterval(refreshAll, REFRESH_INTERVAL_MS)
    return () => clearInterval(id)
  }, [initWindow, refreshAll])

  if (compact) {
    return <CompactView />
  }

  return (
    <>
      <div
        className="overlay"
        style={{ '--overlay-opacity': opacity } as React.CSSProperties}
      >
        <Header />
        <div className="divider" />
        {ALL_PROVIDERS.map((id, i) => (
          <div key={id}>
            <ProviderSection providerID={id} />
            {i < ALL_PROVIDERS.length - 1 && <div className="divider" />}
          </div>
        ))}
        <div className="divider" />
        <Footer />
      </div>

      {showSettings && <Settings />}
    </>
  )
}
