import { useStore } from '../store'
import { PROVIDER_ICONS, PROVIDER_LABELS, EXPAND_DIR_ARROW, EXPAND_DIR_LABEL, type ProviderID, type ProviderState } from '../types'
import { startWindowDrag } from '../utils'

const TINT: Record<ProviderID, string> = {
  claude: '#ff9f0a',
  codex: '#30d158',
  gemini: '#0a84ff',
  antigravity: '#00aaff',
}

// Derive a "current | weekly" pair for any provider shape:
// session/weekly bars (Claude/Codex/Gemini) or the first two quota lanes (Antigravity).
function compactPair(p: ProviderState): { primary: string; secondary: string; primaryFrac: number } {
  if (p.sessionBar || p.weeklyBar) {
    return {
      primary: p.sessionBar ? (p.sessionBar.fraction * 100).toFixed(0) : '—',
      secondary: p.weeklyBar ? (p.weeklyBar.fraction * 100).toFixed(0) : '—',
      primaryFrac: p.sessionBar?.fraction ?? 0,
    }
  }
  if (p.quotaLanes && p.quotaLanes.length) {
    const a = p.quotaLanes[0]
    const b = p.quotaLanes[1]
    return {
      primary: a ? a.pct.toFixed(0) : '—',
      secondary: b ? b.pct.toFixed(0) : '—',
      primaryFrac: a ? a.pct / 100 : 0,
    }
  }
  return { primary: '—', secondary: '—', primaryFrac: 0 }
}

export function CompactView() {
  const menubarSource = useStore(s => s.menubarSource)
  const providers = useStore(s => s.providers)
  const visibleProviders = useStore(s => s.visibleProviders)
  const isLoading = useStore(s => s.isLoading)
  const opacity = useStore(s => s.opacity)
  const autoDim = useStore(s => s.autoDim)
  const setMenubarSource = useStore(s => s.setMenubarSource)
  const setCompact = useStore(s => s.setCompact)
  const hideWindow = useStore(s => s.hideWindow)
  const expandDirection = useStore(s => s.expandDirection)
  const autoResolved = useStore(s => s.autoResolved)
  const isAutoDir = expandDirection === 'auto'
  const shownDir = expandDirection === 'auto' ? autoResolved : expandDirection

  const source = visibleProviders.includes(menubarSource) ? menubarSource : visibleProviders[0]
  const p = providers[source]
  const { primary, secondary, primaryFrac } = compactPair(p)
  const tint = TINT[source]
  const primaryColor =
    primaryFrac >= 1 ? '#ff3b30' : primaryFrac >= 0.9 ? '#ff9f0a' : tint

  // Click the provider chip → cycle to the next visible provider.
  const cycleProvider = () => {
    if (visibleProviders.length < 2) return
    const idx = visibleProviders.indexOf(source)
    setMenubarSource(visibleProviders[(idx + 1) % visibleProviders.length])
  }

  return (
    <div
      className="compact-view"
      style={{ '--idle-opacity': autoDim ? opacity : 1 } as React.CSSProperties}
      onMouseDown={startWindowDrag}
    >
      <button
        className="compact-provider"
        onClick={cycleProvider}
        title="Click to switch provider"
        style={{ color: tint }}
      >
        <span style={{ fontSize: 11 }}>{PROVIDER_ICONS[source]}</span>
        <span className="compact-name">{PROVIDER_LABELS[source]}</span>
      </button>
      <span className="compact-nums">
        <span style={{ color: primaryColor, fontWeight: 700 }}>{primary}%</span>
        <span style={{ color: 'rgba(255,255,255,0.2)' }}> | </span>
        <span style={{ color: 'rgba(255,255,255,0.55)' }}>{secondary}%</span>
      </span>
      <div className="spacer" />
      {isLoading && <span className="spinner" style={{ width: 8, height: 8 }} />}
      <button
        className="icon-btn"
        onClick={() => setCompact(false)}
        title={isAutoDir
          ? `Auto expand ${EXPAND_DIR_ARROW[shownDir]} (${EXPAND_DIR_LABEL[shownDir]})`
          : `Expand ${EXPAND_DIR_LABEL[shownDir]}`}
        style={{ color: isAutoDir ? '#00aaff' : undefined }}
      >
        {EXPAND_DIR_ARROW[shownDir]}
        {isAutoDir && <sub style={{ fontSize: 7, marginLeft: -1 }}>A</sub>}
      </button>
      <button className="icon-btn" onClick={hideWindow} title="Hide">×</button>
    </div>
  )
}
