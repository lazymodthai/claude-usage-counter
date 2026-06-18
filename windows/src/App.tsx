import { useEffect } from 'react'
import { useStore } from './store'
import { Header } from './components/Header'
import { ProviderSection } from './components/ProviderSection'
import { AntigravitySection } from './components/AntigravitySection'
import { Footer } from './components/Footer'
import { Settings } from './components/Settings'
import { CompactView } from './components/CompactView'
import { getCurrentWindow, LogicalSize } from '@tauri-apps/api/window'
import { startWindowDrag } from './utils'
import './App.css'

export function App() {
  const opacity = useStore(s => s.opacity)
  const autoDim = useStore(s => s.autoDim)
  const compact = useStore(s => s.compact)
  const showSettings = useStore(s => s.showSettings)
  const visibleProviders = useStore(s => s.visibleProviders)
  const refreshInterval = useStore(s => s.refreshInterval)
  const refreshAll = useStore(s => s.refreshAll)
  const initWindow = useStore(s => s.initWindow)

  useEffect(() => {
    initWindow()
    refreshAll()
    const id = setInterval(refreshAll, refreshInterval * 1000)
    return () => clearInterval(id)
  }, [initWindow, refreshAll, refreshInterval])

  const hasAntigravity = visibleProviders.includes('antigravity')
  const leftProviders = visibleProviders.filter(id => id !== 'antigravity')
  const usesTwoColumns = hasAntigravity && leftProviders.length > 0

  useEffect(() => {
    if (compact) return
    const win = getCurrentWindow()
    // Honour a size the user has dragged to; otherwise fall back to the
    // layout default (wider when the Antigravity column is shown).
    const saved = localStorage.getItem('windowSize')
    if (saved) {
      try {
        const { w, h } = JSON.parse(saved) as { w: number; h: number }
        // Ignore stale/tiny saved sizes (e.g. a collapsed pill) so we never
        // restore into something that looks "stuck".
        if (w >= 280 && h >= 200) {
          win.setSize(new LogicalSize(w, h)).catch(() => {})
          return
        }
      } catch {}
    }
    const width = usesTwoColumns ? 640 : 320
    win.setSize(new LogicalSize(width, 500)).catch(() => {})
    // Intentionally not depending on `compact`: collapse/expand sizing (and the
    // grow-direction positioning) is owned by setCompact, so re-running here on
    // a compact toggle would fight it. This only refits when columns change.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [usesTwoColumns])

  if (compact) {
    return <CompactView />
  }

  return (
    <>
      <div
        className={`overlay ${usesTwoColumns ? 'two-columns' : ''}`}
        style={{ '--idle-opacity': autoDim ? opacity : 1 } as React.CSSProperties}
        onMouseDown={startWindowDrag}
      >
        <div className="layout-header">
          <Header />
          <div className="divider" />
        </div>
        
        <div className="layout-body">
          <div className="col-left">
            {leftProviders.map((id, i) => (
              <div key={id}>
                <ProviderSection providerID={id} />
                {i < leftProviders.length - 1 && <div className="divider" />}
              </div>
            ))}
          </div>

          {usesTwoColumns && <div className="col-divider" />}

          {hasAntigravity && (
            <div className="col-right">
              <AntigravitySection />
            </div>
          )}
        </div>

        <div className="layout-footer">
          <div className="divider" />
          <Footer />
        </div>
      </div>

      {showSettings && <Settings />}
    </>
  )
}
