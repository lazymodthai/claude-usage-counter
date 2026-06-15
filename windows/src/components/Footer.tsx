import { useStore } from '../store'
import { formatTime } from '../utils'

export function Footer() {
  const menubarSource = useStore(s => s.menubarSource)
  const provider = useStore(s => s.providers[menubarSource])

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
    </div>
  )
}
