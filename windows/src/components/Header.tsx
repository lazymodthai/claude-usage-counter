import { useStore } from '../store'
import { PROVIDER_ICONS } from '../types'

export function Header() {
  const isLoading = useStore(s => s.isLoading)
  const menubarSource = useStore(s => s.menubarSource)
  const refreshAll = useStore(s => s.refreshAll)
  const setShowSettings = useStore(s => s.setShowSettings)
  const setCompact = useStore(s => s.setCompact)
  const hideWindow = useStore(s => s.hideWindow)

  return (
    <div className="header" data-tauri-drag-region>
      <span className={`provider-icon tint-${menubarSource}`} data-tauri-drag-region>
        {PROVIDER_ICONS[menubarSource]}
      </span>
      <span className="header-title" data-tauri-drag-region>AI Usage</span>
      <div className="spacer" data-tauri-drag-region />
      {isLoading && <span className="spinner" />}
      <button className="icon-btn" onClick={refreshAll} title="Refresh">↻</button>
      <button
        className="icon-btn"
        onClick={() => setCompact(true)}
        title="Compact mode (Ctrl+Shift+U)"
        style={{ fontSize: 11 }}
      >⊟</button>
      <button className="icon-btn" onClick={() => setShowSettings(true)} title="Settings">⚙</button>
      <button
        className="icon-btn"
        onClick={hideWindow}
        title="Hide (Ctrl+Shift+U to show again)"
        style={{ fontSize: 14, marginLeft: 2 }}
      >×</button>
    </div>
  )
}
