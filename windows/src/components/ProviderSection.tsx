import { useStore } from '../store'
import { UsageBar } from './UsageBar'
import { PROVIDER_LABELS, PROVIDER_ICONS, type ProviderID } from '../types'

const TINT: Record<ProviderID, string> = {
  claude: '#ff9f0a',
  codex: '#30d158',
  gemini: '#0a84ff',
  antigravity: '#b07aff',
}

interface Props {
  providerID: ProviderID
}

export function ProviderSection({ providerID }: Props) {
  const provider = useStore(s => s.providers[providerID])
  const { authState, sessionBar, weeklyBar, quotaLanes, usingLocal } = provider
  const isConnected = authState === 'signed_in'
  const hasBars = isConnected || providerID === 'claude'
  const tint = TINT[providerID]

  return (
    <div className="provider-section">
      {/* Provider header */}
      <div className="provider-header">
        <span style={{ fontSize: 10, fontWeight: 600, color: tint }}>
          {PROVIDER_ICONS[providerID]}
        </span>
        <span className="provider-name">{PROVIDER_LABELS[providerID]}</span>

        {providerID === 'gemini' && isConnected && (
          <span className="badge">beta</span>
        )}
        {providerID === 'claude' && usingLocal && (
          <span className="badge">local estimate</span>
        )}
        {authState === 'expired' && (
          <span className="badge badge-yellow">session expired</span>
        )}

        <div className="spacer" />

        {!isConnected && (
          <button
            className="sign-in-btn"
            style={{ color: tint }}
            onClick={() => {/* TODO: OAuth login */}}
          >
            {authState === 'expired' ? 'Re-sign in' : 'Sign in'}
          </button>
        )}
      </div>

      {/* Usage bars */}
      {quotaLanes && quotaLanes.length > 0 ? (
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
      ) : hasBars ? (
        <>
          {sessionBar && (
            <UsageBar
              label="Current Session"
              icon="🕐"
              iconColor={tint}
              vm={sessionBar}
            />
          )}
          {weeklyBar && (
            <UsageBar
              label="Weekly"
              icon="📅"
              iconColor="#33ade6"
              vm={weeklyBar}
            />
          )}
        </>
      ) : (
        <span className="not-connected">Not connected</span>
      )}
    </div>
  )
}
