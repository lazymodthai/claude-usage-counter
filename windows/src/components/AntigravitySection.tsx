import { useStore } from '../store'
import { UsageBar } from './UsageBar'
import { PROVIDER_LABELS, PROVIDER_ICONS } from '../types'

export function AntigravitySection() {
  const provider = useStore(s => s.providers.antigravity)
  const { authState, quotaLanes } = provider
  const tint = '#b07aff'

  return (
    <div className="provider-section">
      <div className="provider-header">
        <span style={{ fontSize: 10, fontWeight: 600, color: tint }}>
          {PROVIDER_ICONS.antigravity}
        </span>
        <span className="provider-name">{PROVIDER_LABELS.antigravity}</span>
        <div className="spacer" />
      </div>

      {authState === 'signed_out' ? (
        <span className="not-connected" style={{ display: 'block', marginTop: 8 }}>
          Not running.{' '}
          <a href="https://antigravity.google" target="_blank" rel="noreferrer" style={{color: tint, textDecoration: 'none'}}>
            Open Antigravity
          </a>
        </span>
      ) : (
        <>
          {quotaLanes.map(lane => (
            <UsageBar
              key={lane.id}
              label={lane.label}
              icon="⬡"
              iconColor={tint}
              vm={{
                fraction: lane.pct / 100,
                usedText: `${lane.pct.toFixed(0)}%`,
                limitText: '',
                resetLabel: lane.resetText || '',
                isActive: true
              }}
            />
          ))}
        </>
      )}
    </div>
  )
}
