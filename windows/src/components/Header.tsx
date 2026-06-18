import { useStore } from '../store'
import { PROVIDER_ICONS, EXPAND_DIR_ARROW, EXPAND_DIR_LABEL } from '../types'
import { splitEmojis } from '../utils'

export function Header() {
  const isLoading = useStore(s => s.isLoading)
  const menubarSource = useStore(s => s.menubarSource)
  const petIcon = useStore(s => s.petIcon)
  const refreshAll = useStore(s => s.refreshAll)
  const setShowSettings = useStore(s => s.setShowSettings)
  const setCompact = useStore(s => s.setCompact)
  const hideWindow = useStore(s => s.hideWindow)
  const expandDirection = useStore(s => s.expandDirection)
  const autoResolved = useStore(s => s.autoResolved)
  const cycleExpandDirection = useStore(s => s.cycleExpandDirection)
  const isAutoDir = expandDirection === 'auto'
  const shownDir = expandDirection === 'auto' ? autoResolved : expandDirection

  return (
    <div className="header">
      <span className={`provider-icon tint-${menubarSource}`}>
        {PROVIDER_ICONS[menubarSource]}
      </span>
      <span className="header-title">AI Usage</span>
      {/* Optional decorative pets that stroll back and forth along the header.
          Each gets its own speed/phase so multiple don't move in lockstep. */}
      {splitEmojis(petIcon).map((pet, i) => {
        const anim = { animationDuration: `${11 + i * 2.5}s`, animationDelay: `${-i * 2.7}s` }
        return (
          <span key={i} className="pet-walker" style={anim} aria-hidden="true">
            <span className="pet-face" style={anim}><span className="pet-bob">{pet}</span></span>
          </span>
        )
      })}
      <div className="spacer" />
      {isLoading && <span className="spinner" />}
      <button className="icon-btn" onClick={refreshAll} title="Refresh">↻</button>
      <button
        className="icon-btn"
        onClick={cycleExpandDirection}
        title={isAutoDir
          ? `Auto · ${EXPAND_DIR_LABEL[shownDir]} (click to change)`
          : `${EXPAND_DIR_LABEL[shownDir]} (click to change)`}
        style={{ color: isAutoDir ? '#00aaff' : undefined }}
      >
        {EXPAND_DIR_ARROW[shownDir]}
        {isAutoDir && <sub style={{ fontSize: 7, marginLeft: -1 }}>A</sub>}
      </button>
      <button
        className="icon-btn"
        onClick={() => setCompact(true)}
        title="Collapse mode"
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
