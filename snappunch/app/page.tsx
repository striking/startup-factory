'use client'

import { useState } from 'react'
import { Geist } from 'next/font/google'
import { Analytics } from '@vercel/analytics/react'

const geist = Geist({ subsets: ['latin'] })

export default function Page() {
  const [email, setEmail] = useState('')
  const [isSubmitting, setIsSubmitting] = useState(false)
  const [submitMessage, setSubmitMessage] = useState('')
  const [openFaq, setOpenFaq] = useState<number | null>(null)

  // Waitlist API endpoint - deployed Google Apps Script web app
  const WAITLIST_API_URL = "/api/waitlist";

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!email) return

    setIsSubmitting(true)
    try {
      // Get UTM params from URL
      const urlParams = new URLSearchParams(window.location.search);

      const response = await fetch(WAITLIST_API_URL, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          email,
          product: 'snappunch',
          referrer: document.referrer || '',
          utmSource: urlParams.get('utm_source') || '',
          utmMedium: urlParams.get('utm_medium') || '',
          utmCampaign: urlParams.get('utm_campaign') || ''
        })
      })

      if (response.ok) {
        setSubmitMessage('Thanks! You\'re on the list.')
        setEmail('')
      } else {
        setSubmitMessage('Something went wrong. Try again?')
      }
    } catch (error) {
      setSubmitMessage('Something went wrong. Try again?')
    }
    setIsSubmitting(false)
  }

  const toggleFaq = (index: number) => {
    setOpenFaq(openFaq === index ? null : index)
  }

  return (
    <div className={`${geist.className} min-h-screen bg-slate-950 text-white`}>
      {/* Hero Section */}
      <section className="relative overflow-hidden">
        <div className="absolute inset-0 bg-gradient-to-br from-amber-500/10 via-transparent to-slate-950"></div>
        <div className="relative max-w-6xl mx-auto px-4 py-16 sm:py-24">
          <div className="text-center max-w-4xl mx-auto">
            <div className="inline-flex items-center gap-2 px-4 py-2 rounded-full bg-amber-500/10 border border-amber-500/20 backdrop-blur-sm mb-8">
              <span className="text-amber-400 text-sm font-medium">📸 Invitation Only</span>
            </div>
            
            <h1 className="text-4xl sm:text-6xl lg:text-7xl font-bold mb-6 bg-gradient-to-r from-white via-slate-100 to-slate-300 bg-clip-text text-transparent">
              Snap a photo.<br />
              AI writes the defect report.
            </h1>
            
            <p className="text-xl sm:text-2xl text-slate-300 mb-12 max-w-3xl mx-auto leading-relaxed">
              Stop losing defects scribbled on plans. Stop typing reports after long days. 
              SnapPunch turns photos into professional defect reports instantly.
            </p>

            <form onSubmit={handleSubmit} className="max-w-md mx-auto mb-8">
              <div className="flex gap-3">
                <input
                  type="email"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  placeholder="your.email@company.com.au"
                  className="flex-1 px-4 py-3 rounded-lg bg-slate-800/50 border border-slate-700 backdrop-blur-sm focus:outline-none focus:ring-2 focus:ring-amber-500 focus:border-transparent transition-all"
                  required
                />
                <button
                  type="submit"
                  disabled={isSubmitting}
                  className="px-6 py-3 bg-gradient-to-r from-amber-500 to-amber-600 text-slate-950 font-semibold rounded-lg hover:from-amber-400 hover:to-amber-500 transition-all transform hover:scale-105 disabled:opacity-50"
                >
                  {isSubmitting ? '...' : 'Get Early Access'}
                </button>
              </div>
              {submitMessage && (
                <p className="mt-3 text-sm text-amber-400">{submitMessage}</p>
              )}
            </form>

            <div className="flex items-center justify-center gap-2 text-slate-400">
              <div className="flex -space-x-2">
                <div className="w-8 h-8 rounded-full bg-gradient-to-r from-amber-500 to-orange-500"></div>
                <div className="w-8 h-8 rounded-full bg-gradient-to-r from-blue-500 to-cyan-500"></div>
                <div className="w-8 h-8 rounded-full bg-gradient-to-r from-green-500 to-emerald-500"></div>
              </div>
              <span className="text-sm">Be first to try it</span>
            </div>
          </div>
        </div>
      </section>

      {/* Problem Section */}
      <section className="py-16 sm:py-24">
        <div className="max-w-6xl mx-auto px-4">
          <div className="text-center mb-16">
            <h2 className="text-3xl sm:text-4xl font-bold mb-4">Sound familiar?</h2>
            <p className="text-xl text-slate-300">Every builder knows these pain points</p>
          </div>

          <div className="grid md:grid-cols-3 gap-8">
            <div className="bg-slate-900/50 backdrop-blur-sm border border-slate-800 rounded-xl p-8 hover:border-slate-700 transition-all">
              <div className="text-4xl mb-4">📝</div>
              <blockquote className="text-lg italic text-slate-300 mb-4">
                "Walk through a new build writing defects on the back of a plan. Lost half by Tuesday."
              </blockquote>
              <p className="text-sm text-slate-400">— Site Supervisor, Brisbane</p>
            </div>

            <div className="bg-slate-900/50 backdrop-blur-sm border border-slate-800 rounded-xl p-8 hover:border-slate-700 transition-all">
              <div className="text-4xl mb-4">😴</div>
              <blockquote className="text-lg italic text-slate-300 mb-4">
                "Typing up defect reports after a long day on site — they never get done properly."
              </blockquote>
              <p className="text-sm text-slate-400">— Builder, Melbourne</p>
            </div>

            <div className="bg-slate-900/50 backdrop-blur-sm border border-slate-800 rounded-xl p-8 hover:border-slate-700 transition-all">
              <div className="text-4xl mb-4">📄</div>
              <blockquote className="text-lg italic text-slate-300 mb-4">
                "Inspector sent a 40-page defect report in Word. Half the items don't have photos."
              </blockquote>
              <p className="text-sm text-slate-400">— Project Manager, Sydney</p>
            </div>
          </div>
        </div>
      </section>

      {/* Show Don't Tell Section */}
      <section className="py-16 sm:py-24 bg-gradient-to-b from-slate-950 to-slate-900">
        <div className="max-w-6xl mx-auto px-4">
          <div className="text-center mb-16">
            <h2 className="text-3xl sm:text-4xl font-bold mb-4">From this mess...</h2>
            <p className="text-xl text-slate-300">See the difference SnapPunch makes</p>
          </div>

          <div className="grid lg:grid-cols-2 gap-12 items-center">
            {/* Before */}
            <div className="space-y-4">
              <div className="flex items-center gap-3 mb-6">
                <div className="w-8 h-8 rounded-full bg-red-500/20 flex items-center justify-center">
                  <span className="text-red-400 text-sm">❌</span>
                </div>
                <h3 className="text-xl font-semibold text-red-400">Before: Handwritten chaos</h3>
              </div>
              
              <div className="bg-yellow-50 p-6 rounded-lg transform rotate-1 shadow-lg">
                <div className="space-y-2 text-slate-800">
                  <div className="border-b border-slate-300 pb-1 mb-3">
                    <span className="text-sm text-slate-600">Defects - Unit 12A</span>
                  </div>
                  <div className="handwriting text-sm space-y-1">
                    <div className="transform -rotate-1">bathroom - cracked tile?</div>
                    <div className="transform rotate-1">kitchen tap leaking</div>
                    <div className="transform -rotate-1 line-through">door handle loose</div>
                    <div className="transform rotate-1">paint touch up needed</div>
                    <div className="transform -rotate-1">window won't close</div>
                    <div className="text-xs text-slate-500 mt-3">No photos, no room details, illegible notes</div>
                  </div>
                </div>
              </div>
            </div>

            {/* After */}
            <div className="space-y-4">
              <div className="flex items-center gap-3 mb-6">
                <div className="w-8 h-8 rounded-full bg-green-500/20 flex items-center justify-center">
                  <span className="text-green-400 text-sm">✅</span>
                </div>
                <h3 className="text-xl font-semibold text-green-400">After: Professional reports</h3>
              </div>

              <div className="bg-slate-800/50 backdrop-blur-sm border border-slate-700 rounded-xl p-6 hover:border-amber-500/50 transition-all">
                <div className="flex items-start gap-4">
                  <div className="w-16 h-16 bg-gradient-to-br from-amber-500 to-orange-500 rounded-lg flex items-center justify-center text-2xl">
                    📸
                  </div>
                  <div className="flex-1">
                    <div className="flex items-center gap-2 mb-2">
                      <span className="px-2 py-1 bg-amber-500/20 text-amber-400 text-xs rounded-full">Master Ensuite</span>
                      <span className="px-2 py-1 bg-red-500/20 text-red-400 text-xs rounded-full">Open</span>
                    </div>
                    <h4 className="font-semibold mb-2">Cracked tile — 300x300 porcelain, NW corner</h4>
                    <p className="text-sm text-slate-400 mb-3">Hairline crack visible across centre of tile. Likely installation issue.</p>
                    <div className="flex items-center justify-between text-xs text-slate-500">
                      <span>Assigned: AJ Tiling</span>
                      <span>Priority: Medium</span>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* How It Works */}
      <section className="py-16 sm:py-24">
        <div className="max-w-6xl mx-auto px-4">
          <div className="text-center mb-16">
            <h2 className="text-3xl sm:text-4xl font-bold mb-4">How it works</h2>
            <p className="text-xl text-slate-300">Three steps to professional defect reports</p>
          </div>

          <div className="grid md:grid-cols-3 gap-8">
            <div className="text-center group">
              <div className="w-16 h-16 bg-gradient-to-r from-amber-500 to-orange-500 rounded-full flex items-center justify-center text-2xl mx-auto mb-6 group-hover:scale-110 transition-transform">
                📱
              </div>
              <div className="w-8 h-8 bg-amber-500 text-slate-950 rounded-full flex items-center justify-center text-sm font-bold mx-auto mb-4">1</div>
              <h3 className="text-xl font-semibold mb-3">Walk site, snap photos</h3>
              <p className="text-slate-400">Point your phone at any defect. SnapPunch captures the photo and location automatically.</p>
            </div>

            <div className="text-center group">
              <div className="w-16 h-16 bg-gradient-to-r from-blue-500 to-cyan-500 rounded-full flex items-center justify-center text-2xl mx-auto mb-6 group-hover:scale-110 transition-transform">
                🤖
              </div>
              <div className="w-8 h-8 bg-amber-500 text-slate-950 rounded-full flex items-center justify-center text-sm font-bold mx-auto mb-4">2</div>
              <h3 className="text-xl font-semibold mb-3">AI identifies issue, writes description</h3>
              <p className="text-slate-400">Our AI analyses the photo, identifies the defect type, and writes a detailed description.</p>
            </div>

            <div className="text-center group">
              <div className="w-16 h-16 bg-gradient-to-r from-green-500 to-emerald-500 rounded-full flex items-center justify-center text-2xl mx-auto mb-6 group-hover:scale-110 transition-transform">
                📄
              </div>
              <div className="w-8 h-8 bg-amber-500 text-slate-950 rounded-full flex items-center justify-center text-sm font-bold mx-auto mb-4">3</div>
              <h3 className="text-xl font-semibold mb-3">Export professional report</h3>
              <p className="text-slate-400">Generate PDF reports, assign to subcontractors, and track progress until completion.</p>
            </div>
          </div>
        </div>
      </section>

      {/* Features */}
      <section className="py-16 sm:py-24 bg-slate-900/30">
        <div className="max-w-6xl mx-auto px-4">
          <div className="text-center mb-16">
            <h2 className="text-3xl sm:text-4xl font-bold mb-4">Everything you need</h2>
            <p className="text-xl text-slate-300">Built for Australian construction workflows</p>
          </div>

          <div className="grid md:grid-cols-2 lg:grid-cols-3 gap-8">
            <div className="bg-slate-800/30 backdrop-blur-sm border border-slate-700 rounded-xl p-6 hover:border-amber-500/50 transition-all">
              <div className="text-3xl mb-4">🔍</div>
              <h3 className="text-lg font-semibold mb-2">Photo AI Analysis</h3>
              <p className="text-slate-400">Automatically identifies defect types, materials, and severity from photos.</p>
            </div>

            <div className="bg-slate-800/30 backdrop-blur-sm border border-slate-700 rounded-xl p-6 hover:border-amber-500/50 transition-all">
              <div className="text-3xl mb-4">🏠</div>
              <h3 className="text-lg font-semibold mb-2">Room Tagging</h3>
              <p className="text-slate-400">Smart location detection organises defects by room and area automatically.</p>
            </div>

            <div className="bg-slate-800/30 backdrop-blur-sm border border-slate-700 rounded-xl p-6 hover:border-amber-500/50 transition-all">
              <div className="text-3xl mb-4">✍️</div>
              <h3 className="text-lg font-semibold mb-2">Auto-Descriptions</h3>
              <p className="text-slate-400">Professional defect descriptions written in proper construction terminology.</p>
            </div>

            <div className="bg-slate-800/30 backdrop-blur-sm border border-slate-700 rounded-xl p-6 hover:border-amber-500/50 transition-all">
              <div className="text-3xl mb-4">📋</div>
              <h3 className="text-lg font-semibold mb-2">PDF Export</h3>
              <p className="text-slate-400">Generate professional reports ready to send to clients and subcontractors.</p>
            </div>

            <div className="bg-slate-800/30 backdrop-blur-sm border border-slate-700 rounded-xl p-6 hover:border-amber-500/50 transition-all">
              <div className="text-3xl mb-4">👷</div>
              <h3 className="text-lg font-semibold mb-2">Subcontractor Assignment</h3>
              <p className="text-slate-400">Assign defects to specific trades and track their progress to completion.</p>
            </div>

            <div className="bg-slate-800/30 backdrop-blur-sm border border-slate-700 rounded-xl p-6 hover:border-amber-500/50 transition-all">
              <div className="text-3xl mb-4">📊</div>
              <h3 className="text-lg font-semibold mb-2">Progress Tracking</h3>
              <p className="text-slate-400">Real-time status updates from open to in-progress to completed.</p>
            </div>
          </div>
        </div>
      </section>

      {/* Social Proof */}
      <section className="py-16 sm:py-24">
        <div className="max-w-4xl mx-auto px-4 text-center">
          <div className="bg-slate-900/50 backdrop-blur-sm border border-slate-800 rounded-2xl p-8 sm:p-12">
            <div className="text-4xl mb-6">🇦🇺</div>
            <h2 className="text-2xl sm:text-3xl font-bold mb-4">Built for Australian construction</h2>
            <p className="text-lg text-slate-300 mb-8">
              Developed with input from builders, site supervisors, and building inspectors across Australia. 
              Understands local building codes, terminology, and workflows.
            </p>
            <div className="flex flex-wrap justify-center gap-4">
              <span className="px-4 py-2 bg-amber-500/10 border border-amber-500/20 rounded-full text-amber-400 text-sm">Australian Standards</span>
              <span className="px-4 py-2 bg-amber-500/10 border border-amber-500/20 rounded-full text-amber-400 text-sm">Local Terminology</span>
              <span className="px-4 py-2 bg-amber-500/10 border border-amber-500/20 rounded-full text-amber-400 text-sm">Industry Workflows</span>
            </div>
          </div>
        </div>
      </section>

      {/* FAQ */}
      <section className="py-16 sm:py-24 bg-slate-900/30">
        <div className="max-w-4xl mx-auto px-4">
          <div className="text-center mb-16">
            <h2 className="text-3xl sm:text-4xl font-bold mb-4">Common questions</h2>
            <p className="text-xl text-slate-300">Everything you need to know</p>
          </div>

          <div className="space-y-4">
            {[
              {
                q: "How accurate is the AI defect identification?",
                a: "Our AI has been trained on thousands of construction defects and achieves 95%+ accuracy on common issues like cracks, paint defects, and installation problems. You can always edit descriptions before generating reports."
              },
              {
                q: "Does it work offline on construction sites?",
                a: "Yes! SnapPunch works offline to capture photos and basic data. When you're back online, the AI processes everything and syncs your reports to the cloud."
              },
              {
                q: "Can I customise the report format?",
                a: "Absolutely. You can add your company branding, adjust report layouts, and include custom fields that match your existing workflows."
              },
              {
                q: "What about data security and privacy?",
                a: "All data is encrypted and stored on Australian servers. We're SOC 2 compliant and never share your project data with third parties."
              },
              {
                q: "When will SnapPunch be available?",
                a: "We're onboarding early access members now. Request your spot and we'll be in touch."
              }
            ].map((faq, index) => (
              <div key={index} className="bg-slate-800/30 backdrop-blur-sm border border-slate-700 rounded-xl overflow-hidden">
                <button
                  onClick={() => toggleFaq(index)}
                  className="w-full px-6 py-4 text-left flex items-center justify-between hover:bg-slate-800/50 transition-all"
                >
                  <span className="font-semibold">{faq.q}</span>
                  <span className={`transform transition-transform ${openFaq === index ? 'rotate-180' : ''}`}>
                    ⌄
                  </span>
                </button>
                {openFaq === index && (
                  <div className="px-6 pb-4 text-slate-300">
                    {faq.a}
                  </div>
                )}
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* Final CTA */}
      <section className="py-16 sm:py-24">
        <div className="max-w-4xl mx-auto px-4 text-center">
          <div className="bg-gradient-to-r from-amber-500/10 via-orange-500/10 to-amber-500/10 backdrop-blur-sm border border-amber-500/20 rounded-2xl p-8 sm:p-12">
            <h2 className="text-3xl sm:text-4xl font-bold mb-4">Ready to ditch the paperwork?</h2>
            <p className="text-xl text-slate-300 mb-8">
              Request early access. Limited spots available.
            </p>

            <form onSubmit={handleSubmit} className="max-w-md mx-auto mb-6">
              <div className="flex gap-3">
                <input
                  type="email"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  placeholder="your.email@company.com.au"
                  className="flex-1 px-4 py-3 rounded-lg bg-slate-800/50 border border-slate-700 backdrop-blur-sm focus:outline-none focus:ring-2 focus:ring-amber-500 focus:border-transparent transition-all"
                  required
                />
                <button
                  type="submit"
                  disabled={isSubmitting}
                  className="px-6 py-3 bg-gradient-to-r from-amber-500 to-amber-600 text-slate-950 font-semibold rounded-lg hover:from-amber-400 hover:to-amber-500 transition-all transform hover:scale-105 disabled:opacity-50"
                >
                  {isSubmitting ? '...' : 'Get Early Access'}
                </button>
              </div>
              {submitMessage && (
                <p className="mt-3 text-sm text-amber-400">{submitMessage}</p>
              )}
            </form>

            <p className="text-sm text-slate-400">
              ⚡ Limited spots available • 🎯 No spam, just updates • 🇦🇺 Australian-first
            </p>
          </div>
        </div>
      </section>

      {/* Footer */}
      <footer className="py-8 border-t border-slate-800">
        <div className="max-w-6xl mx-auto px-4 text-center">
          <p className="text-slate-400">
            Built by{' '}
            <a 
              href="https://levasolutions.com.au" 
              target="_blank" 
              rel="noopener noreferrer"
              className="text-amber-400 hover:text-amber-300 transition-colors"
            >
              Leva Solutions
            </a>
          </p>
        </div>
      </footer>

      <Analytics />
    </div>
  )
}