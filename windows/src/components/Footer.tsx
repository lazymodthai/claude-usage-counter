import { useStore } from '../store'
import { formatTime } from '../utils'

export function Footer() {
  const menubarSource = useStore(s => s.menubarSource)
  const provider = useStore(s => s.providers[menubarSource])
  const opacity = useStore(s => s.opacity)
  const autoDim = useStore(s => s.autoDim)
  const setOpacity = useStore(s => s.setOpacity)

  const isLive = provider.authState === 'signed_in' && provider.sessionBar !== null
  const updatedAt = provider.fetchedAt ?? new Date()

  return (
    <div className="footer">
      {isLive && (
        <>
          <span style={{ fontSize: 9, color: '#30d158' }}>◉</span>
          <span className="footer-text" style={{ color: '#30d158cc' }}>
            Live · {menubarSource.charAt(0).toUpperCase() + menubarSource.slice(1)}
          </span>
          <span className="footer-text" style={{ color: 'rgba(255,255,255,0.2)' }}>·</span>
        </>
      )}
      <span className="footer-text">Updated {formatTime(updatedAt)}</span>

      <div style={{ marginLeft: 'auto', display: 'flex', alignItems: 'center', gap: 6, opacity: autoDim ? 1 : 0.4, pointerEvents: autoDim ? 'auto' : 'none' }}>
        <span className="footer-text" style={{ opacity: 0.6 }}>Opacity</span>
        <input
          type="range"
          min={0.15}
          max={1}
          step={0.05}
          value={opacity}
          onChange={e => setOpacity(parseFloat(e.target.value))}
          className="slider"
          style={{ width: 60 }}
        />
      </div>
    </div>
  )
}
