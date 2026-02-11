'use client'

import { useState, useEffect } from 'react'

export default function AriaCommandCenter() {
  const [currentTime, setCurrentTime] = useState('')

  useEffect(() => {
    const updateTime = () => {
      const now = new Date()
      const options: Intl.DateTimeFormatOptions = {
        timeZone: 'Australia/Brisbane',
        hour: '2-digit',
        minute: '2-digit',
        second: '2-digit',
        hour12: false
      }
      setCurrentTime(now.toLocaleTimeString('en-AU', options) + ' AEST')
    }

    updateTime()
    const interval = setInterval(updateTime, 1000)
    return () => clearInterval(interval)
  }, [])

  // Mock data
  const systemHealth = {
    gateway: { status: 'green', label: 'Gateway' },
    tts: { status: 'green', label: 'TTS' },
    browser: { status: 'yellow', label: 'Browser' },
    emailHooks: { status: 'green', label: 'Email Hooks' }
  }

  const cronJobs = [
    { name: 'Email Digest', schedule: '0 8 * * *', status: '✅', nextRun: '2026-02-09 08:00', type: 'healthy' },
    { name: 'LinkedIn Outreach', schedule: '0 10 * * 1-5', status: '✅', nextRun: '2026-02-10 10:00', type: 'healthy' },
    { name: 'Lead Scoring', schedule: '*/15 * * * *', status: '✅', nextRun: '2026-02-08 06:30', type: 'upcoming' },
    { name: 'Social Monitoring', schedule: '*/30 * * * *', status: '✅', nextRun: '2026-02-08 06:30', type: 'upcoming' },
    { name: 'Domain Health Check', schedule: '0 6 * * *', status: '❌', nextRun: '2026-02-09 06:00', type: 'failed' },
    { name: 'Market Research', schedule: '0 14 * * 1', status: '✅', nextRun: '2026-02-10 14:00', type: 'healthy' },
    { name: 'Competitor Analysis', schedule: '0 16 * * 3', status: '✅', nextRun: '2026-02-12 16:00', type: 'healthy' },
    { name: 'Content Backup', schedule: '0 2 * * *', status: '✅', nextRun: '2026-02-09 02:00', type: 'healthy' },
    { name: 'Analytics Report', schedule: '0 9 * * 1', status: '✅', nextRun: '2026-02-10 09:00', type: 'healthy' },
    { name: 'API Health Check', schedule: '*/10 * * * *', status: '✅', nextRun: '2026-02-08 06:30', type: 'upcoming' },
    { name: 'Lead Nurturing', schedule: '0 11 * * 2,4', status: '✅', nextRun: '2026-02-11 11:00', type: 'healthy' },
    { name: 'Database Cleanup', schedule: '0 3 * * 0', status: '✅', nextRun: '2026-02-09 03:00', type: 'healthy' },
    { name: 'Security Scan', schedule: '0 1 * * *', status: '❌', nextRun: '2026-02-09 01:00', type: 'failed' },
    { name: 'Revenue Tracking', schedule: '0 23 * * *', status: '✅', nextRun: '2026-02-08 23:00', type: 'upcoming' },
    { name: 'Customer Insights', schedule: '0 12 * * 1-5', status: '✅', nextRun: '2026-02-10 12:00', type: 'healthy' }
  ]

  const leads = [
    { name: 'TechCorp Solutions', source: 'LinkedIn', value: '$45k', stage: 'Hot', days: 3 },
    { name: 'BuildFast Inc', source: 'Cold Email', value: '$28k', stage: 'Hot', days: 7 },
    { name: 'StartupLab', source: 'Referral', value: '$18k', stage: 'Warm', days: 12 },
    { name: 'ScaleUp Ventures', source: 'Twitter', value: '$65k', stage: 'Warm', days: 8 },
    { name: 'CodeHouse', source: 'LinkedIn', value: '$22k', stage: 'Cold', days: 21 },
    { name: 'DevCorp Pro', source: 'Website', value: '$85k', stage: 'Won', days: 45 }
  ]

  const todos = [
    { text: 'Close TechCorp deal', priority: '🔴', category: 'Revenue', status: 'active' },
    { text: 'Launch SnapPunch marketing', priority: '🔴', category: 'Revenue', status: 'active' },
    { text: 'Follow up BuildFast proposal', priority: '🟠', category: 'Pipeline', status: 'pending' },
    { text: 'Complete Qwoted MVP', priority: '🟡', category: 'Build', status: 'active' },
    { text: 'Fix domain redirects', priority: '🟡', category: 'Build', status: 'pending' },
    { text: 'Update LinkedIn automation', priority: '🟠', category: 'Pipeline', status: 'active' },
    { text: 'Research new verticals', priority: '🟢', category: 'Growth', status: 'pending' },
    { text: 'Optimize landing pages', priority: '🟡', category: 'Build', status: 'pending' },
    { text: 'Content calendar planning', priority: '🟢', category: 'Growth', status: 'pending' },
    { text: 'Partnership outreach', priority: '🟢', category: 'Growth', status: 'pending' }
  ]

  const startups = [
    { name: 'TextTime', status: 'Live', url: 'texttime.com', waitlist: 1247, mrr: 2800 },
    { name: 'SnapPunch', status: 'Building', url: 'snappunch.com', waitlist: 892, mrr: 0 }
  ]

  const activities = [
    { icon: '🚀', text: 'Deployed SnapPunch v2.1', time: '2 hours ago' },
    { icon: '📧', text: 'Processed 12 emails', time: '3 hours ago' },
    { icon: '📝', text: 'Drafted Qwoted pitch deck', time: '4 hours ago' },
    { icon: '🔗', text: 'Connected with 5 prospects', time: '5 hours ago' },
    { icon: '📊', text: 'Updated revenue tracking', time: '6 hours ago' },
    { icon: '🎯', text: 'Qualified 3 new leads', time: '8 hours ago' },
    { icon: '🔧', text: 'Fixed TextTime bug #247', time: '12 hours ago' },
    { icon: '📱', text: 'Social media posting', time: '1 day ago' },
    { icon: '💰', text: 'Invoice sent to TechCorp', time: '1 day ago' },
    { icon: '🤝', text: 'Partnership meeting', time: '2 days ago' }
  ]

  const getStatusColor = (status: string) => {
    switch (status) {
      case 'green': return 'bg-green-500'
      case 'yellow': return 'bg-yellow-500'
      case 'red': return 'bg-red-500'
      default: return 'bg-gray-500'
    }
  }

  const getCronTypeColor = (type: string) => {
    switch (type) {
      case 'healthy': return 'border-green-500 bg-green-500/10'
      case 'failed': return 'border-red-500 bg-red-500/10'
      case 'upcoming': return 'border-yellow-500 bg-yellow-500/10'
      default: return 'border-gray-500 bg-gray-500/10'
    }
  }

  const getStageColor = (stage: string) => {
    switch (stage) {
      case 'Hot': return 'bg-red-500/20 border-red-500'
      case 'Warm': return 'bg-orange-500/20 border-orange-500'
      case 'Cold': return 'bg-blue-500/20 border-blue-500'
      case 'Won': return 'bg-green-500/20 border-green-500'
      case 'Lost': return 'bg-gray-500/20 border-gray-500'
      default: return 'bg-gray-500/20 border-gray-500'
    }
  }

  return (
    <div className="min-h-screen bg-slate-950 text-slate-100">
      {/* Header */}
      <header className="bg-slate-900 border-b border-slate-800 px-4 py-4">
        <div className="max-w-7xl mx-auto flex items-center justify-between">
          <h1 className="text-2xl font-bold text-white">Aria Command Center 🎵</h1>
          <div className="text-slate-300 font-mono">{currentTime}</div>
        </div>
      </header>

      <div className="max-w-7xl mx-auto px-4 py-6 space-y-6">
        {/* System Health */}
        <div className="bg-slate-900 rounded-lg border border-slate-800 p-4">
          <h2 className="text-lg font-semibold mb-4 text-white">System Health</h2>
          <div className="flex flex-wrap gap-4 items-center">
            {Object.entries(systemHealth).map(([key, { status, label }]) => (
              <div key={key} className="flex items-center gap-2">
                <div className={`w-3 h-3 rounded-full ${getStatusColor(status)}`}></div>
                <span className="text-sm text-slate-300">{label}</span>
              </div>
            ))}
            <div className="ml-auto flex gap-6 text-sm text-slate-400">
              <span>Last heartbeat: 2 min ago</span>
              <span>Today's API cost: $23.47</span>
            </div>
          </div>
        </div>

        {/* Active Crons */}
        <div className="bg-slate-900 rounded-lg border border-slate-800 p-4">
          <h2 className="text-lg font-semibold mb-4 text-white">Active Crons</h2>
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            {cronJobs.map((cron, index) => (
              <div key={index} className={`p-3 rounded border ${getCronTypeColor(cron.type)}`}>
                <div className="flex items-center justify-between mb-2">
                  <span className="font-medium text-sm text-white">{cron.name}</span>
                  <span className="text-lg">{cron.status}</span>
                </div>
                <div className="text-xs text-slate-400 space-y-1">
                  <div>Schedule: {cron.schedule}</div>
                  <div>Next: {cron.nextRun}</div>
                </div>
              </div>
            ))}
          </div>
        </div>

        {/* Lead Pipeline */}
        <div className="bg-slate-900 rounded-lg border border-slate-800 p-4">
          <h2 className="text-lg font-semibold mb-4 text-white">Lead Pipeline</h2>
          <div className="grid grid-cols-1 md:grid-cols-3 lg:grid-cols-5 gap-4">
            {['Hot', 'Warm', 'Cold', 'Won', 'Lost'].map(stage => (
              <div key={stage} className="space-y-2">
                <h3 className="font-semibold text-white border-b border-slate-700 pb-2">{stage}</h3>
                <div className="space-y-2">
                  {leads.filter(lead => lead.stage === stage).map((lead, index) => (
                    <div key={index} className={`p-3 rounded border ${getStageColor(stage)}`}>
                      <div className="font-medium text-sm text-white mb-1">{lead.name}</div>
                      <div className="text-xs text-slate-400 space-y-1">
                        <div>Source: {lead.source}</div>
                        <div>Value: {lead.value}</div>
                        <div>{lead.days} days in stage</div>
                      </div>
                    </div>
                  ))}
                </div>
              </div>
            ))}
          </div>
        </div>

        {/* TODO Priorities */}
        <div className="bg-slate-900 rounded-lg border border-slate-800 p-4">
          <h2 className="text-lg font-semibold mb-4 text-white">TODO Priorities</h2>
          <div className="space-y-2">
            {todos.map((todo, index) => (
              <div key={index} className="flex items-center gap-3 p-3 bg-slate-800 rounded border border-slate-700">
                <span className="text-lg">{todo.priority}</span>
                <span className="flex-1 text-white">{todo.text}</span>
                <span className="text-xs text-slate-400 px-2 py-1 bg-slate-700 rounded">{todo.category}</span>
                <div className={`w-2 h-2 rounded-full ${todo.status === 'active' ? 'bg-green-500' : 'bg-yellow-500'}`}></div>
              </div>
            ))}
          </div>
        </div>

        {/* Startup Factory */}
        <div className="bg-slate-900 rounded-lg border border-slate-800 p-4">
          <h2 className="text-lg font-semibold mb-4 text-white">Startup Factory</h2>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            {startups.map((startup, index) => (
              <div key={index} className="p-4 bg-slate-800 rounded border border-slate-700">
                <div className="flex items-center justify-between mb-3">
                  <h3 className="font-semibold text-white">{startup.name}</h3>
                  <span className={`px-2 py-1 text-xs rounded ${startup.status === 'Live' ? 'bg-green-500/20 text-green-300' : 'bg-yellow-500/20 text-yellow-300'}`}>
                    {startup.status}
                  </span>
                </div>
                <div className="space-y-2 text-sm text-slate-400">
                  <div>URL: {startup.url}</div>
                  <div>Waitlist: {startup.waitlist.toLocaleString()}</div>
                  <div>MRR: ${startup.mrr.toLocaleString()}</div>
                </div>
              </div>
            ))}
          </div>
        </div>

        {/* Recent Activity */}
        <div className="bg-slate-900 rounded-lg border border-slate-800 p-4">
          <h2 className="text-lg font-semibold mb-4 text-white">Recent Activity</h2>
          <div className="space-y-3">
            {activities.map((activity, index) => (
              <div key={index} className="flex items-center gap-3 p-3 bg-slate-800 rounded">
                <span className="text-lg">{activity.icon}</span>
                <span className="flex-1 text-white">{activity.text}</span>
                <span className="text-xs text-slate-400">{activity.time}</span>
              </div>
            ))}
          </div>
        </div>

        {/* Quick Stats Footer */}
        <div className="bg-slate-900 rounded-lg border border-slate-800 p-4">
          <div className="grid grid-cols-2 md:grid-cols-4 gap-4 text-center">
            <div>
              <div className="text-2xl font-bold text-white">45</div>
              <div className="text-sm text-slate-400">Emails processed today</div>
            </div>
            <div>
              <div className="text-2xl font-bold text-white">3,663</div>
              <div className="text-sm text-slate-400">LinkedIn connections</div>
            </div>
            <div>
              <div className="text-2xl font-bold text-white">81</div>
              <div className="text-sm text-slate-400">Domains owned</div>
            </div>
            <div>
              <div className="text-2xl font-bold text-white">15</div>
              <div className="text-sm text-slate-400">Active crons</div>
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}