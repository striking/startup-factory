'use client'

import { useState } from 'react'
import { Geist } from 'next/font/google'
import { Analytics } from '@vercel/analytics/react'

const geist = Geist({ subsets: ['latin'] })

export default function Page() {
  const [email, setEmail] = useState('')
  const [isSubmitting, setIsSubmitting] = useState(false)
  const [isSubmitted, setIsSubmitted] = useState(false)
  const [openFaq, setOpenFaq] = useState<number | null>(null)

  // Waitlist API endpoint - deployed Google Apps Script web app
  const WAITLIST_API_URL = "/api/waitlist";

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!email || isSubmitting) return

    setIsSubmitting(true)

    try {
      // Get UTM params from URL
      const urlParams = new URLSearchParams(window.location.search);

      const response = await fetch(WAITLIST_API_URL, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          email,
          product: 'scopemate',
          referrer: document.referrer || '',
          utmSource: urlParams.get('utm_source') || '',
          utmMedium: urlParams.get('utm_medium') || '',
          utmCampaign: urlParams.get('utm_campaign') || ''
        })
      })

      if (response.ok) {
        setIsSubmitted(true)
        setEmail('')
      }
    } catch (error) {
      console.error('Submission error:', error)
    } finally {
      setIsSubmitting(false)
    }
  }

  const WaitlistForm = ({ showUrgency = false }: { showUrgency?: boolean }) => (
    <div className="w-full max-w-md mx-auto">
      {isSubmitted ? (
        <div className="bg-gradient-to-r from-purple-500/20 to-violet-500/20 backdrop-blur-sm border border-purple-500/30 rounded-xl p-6 text-center">
          <div className="text-2xl mb-2">🎉</div>
          <h3 className="text-lg font-semibold text-white mb-2">You're on the list!</h3>
          <p className="text-slate-300 text-sm">We'll send you early access when it's ready.</p>
        </div>
      ) : (
        <form onSubmit={handleSubmit} className="space-y-4">
          {showUrgency && (
            <div className="text-center mb-4">
              <span className="inline-flex items-center px-3 py-1 rounded-full text-xs font-medium bg-gradient-to-r from-purple-500/20 to-violet-500/20 text-purple-300 border border-purple-500/30">
                🔥 Limited early access spots
              </span>
            </div>
          )}
          <div className="flex flex-col sm:flex-row gap-3">
            <input
              type="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              placeholder="Enter your email"
              required
              className="flex-1 px-4 py-3 bg-slate-800/50 backdrop-blur-sm border border-slate-700/50 rounded-lg text-white placeholder-slate-400 focus:outline-none focus:ring-2 focus:ring-purple-500/50 focus:border-purple-500/50 transition-all duration-200"
            />
            <button
              type="submit"
              disabled={isSubmitting}
              className="px-6 py-3 bg-gradient-to-r from-purple-600 to-violet-600 hover:from-purple-500 hover:to-violet-500 text-white font-medium rounded-lg transition-all duration-200 transform hover:scale-105 disabled:opacity-50 disabled:cursor-not-allowed disabled:transform-none whitespace-nowrap"
            >
              {isSubmitting ? 'Joining...' : 'Request Early Access'}
            </button>
          </div>
          <p className="text-xs text-slate-400 text-center">
            Invitation only. No spam, unsubscribe anytime.
          </p>
        </form>
      )}
    </div>
  )

  return (
    <div className={`min-h-screen bg-slate-950 text-white ${geist.className}`}>
      {/* Hero Section */}
      <section className="relative overflow-hidden">
        <div className="absolute inset-0 bg-gradient-to-br from-purple-900/20 via-slate-950 to-violet-900/20"></div>
        <div className="relative max-w-6xl mx-auto px-4 sm:px-6 lg:px-8 pt-20 pb-32">
          <div className="text-center space-y-8">
            <div className="space-y-4">
              <span className="inline-flex items-center px-3 py-1 rounded-full text-sm font-medium bg-gradient-to-r from-purple-500/20 to-violet-500/20 text-purple-300 border border-purple-500/30">
                🚀 Early Access
              </span>
              <h1 className="text-4xl sm:text-5xl lg:text-6xl font-bold leading-tight">
                Turn job photos into
                <span className="bg-gradient-to-r from-purple-400 to-violet-400 bg-clip-text text-transparent"> accurate scopes</span>
              </h1>
              <p className="text-xl sm:text-2xl text-slate-300 max-w-3xl mx-auto leading-relaxed">
                Stop losing money on vague scopes. ScopeMate turns your site photos into detailed, professional scope of works that protect your business.
              </p>
            </div>
            
            <WaitlistForm />
            
            <div className="flex items-center justify-center space-x-8 text-sm text-slate-400">
              <div className="flex items-center space-x-2">
                <div className="w-2 h-2 bg-green-500 rounded-full animate-pulse"></div>
                <span>Early access open</span>
              </div>
              <div className="flex items-center space-x-2">
                <span>🇦🇺</span>
                <span>Built for Australian trades</span>
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* Problem Section */}
      <section className="py-20 px-4 sm:px-6 lg:px-8">
        <div className="max-w-6xl mx-auto">
          <div className="text-center mb-16">
            <h2 className="text-3xl sm:text-4xl font-bold mb-4">
              Sound familiar?
            </h2>
            <p className="text-xl text-slate-300">
              Every builder knows these pain points
            </p>
          </div>
          
          <div className="grid md:grid-cols-3 gap-8">
            <div className="bg-slate-900/50 backdrop-blur-sm border border-slate-800/50 rounded-xl p-6 hover:border-purple-500/30 transition-all duration-300">
              <div className="text-3xl mb-4">😤</div>
              <blockquote className="text-slate-300 italic mb-4">
                "Writing a scope takes my entire Sunday arvo. $200K reno and the scope is a half-page email."
              </blockquote>
              <div className="text-sm text-slate-400">— Dave, Custom Builder</div>
            </div>
            
            <div className="bg-slate-900/50 backdrop-blur-sm border border-slate-800/50 rounded-xl p-6 hover:border-purple-500/30 transition-all duration-300">
              <div className="text-3xl mb-4">🤦‍♂️</div>
              <blockquote className="text-slate-300 italic mb-4">
                "Client says splashback was included. Wasn't in scope because scope was 3 dot points."
              </blockquote>
              <div className="text-sm text-slate-400">— Sarah, Renovator</div>
            </div>
            
            <div className="bg-slate-900/50 backdrop-blur-sm border border-slate-800/50 rounded-xl p-6 hover:border-purple-500/30 transition-all duration-300">
              <div className="text-3xl mb-4">💸</div>
              <blockquote className="text-slate-300 italic mb-4">
                "Lost a $15K variation dispute because original scope didn't clearly exclude it."
              </blockquote>
              <div className="text-sm text-slate-400">— Mark, Project Manager</div>
            </div>
          </div>
        </div>
      </section>

      {/* Show Don't Tell Section */}
      <section className="py-20 px-4 sm:px-6 lg:px-8 bg-gradient-to-b from-slate-950 to-slate-900/50">
        <div className="max-w-6xl mx-auto">
          <div className="text-center mb-16">
            <h2 className="text-3xl sm:text-4xl font-bold mb-4">
              From this mess...
              <span className="bg-gradient-to-r from-purple-400 to-violet-400 bg-clip-text text-transparent"> to professional scope</span>
            </h2>
            <p className="text-xl text-slate-300">
              See the difference in 3 seconds
            </p>
          </div>
          
          <div className="grid lg:grid-cols-2 gap-8 items-start">
            {/* Before */}
            <div className="space-y-4">
              <div className="flex items-center space-x-2 mb-4">
                <span className="px-3 py-1 bg-red-500/20 text-red-300 rounded-full text-sm font-medium border border-red-500/30">
                  ❌ Before
                </span>
                <span className="text-slate-400 text-sm">Typical builder email</span>
              </div>
              <div className="bg-slate-800/50 backdrop-blur-sm border border-slate-700/50 rounded-xl p-6">
                <div className="space-y-3 text-slate-300">
                  <div className="text-sm text-slate-400">Subject: Bathroom Quote</div>
                  <div className="border-t border-slate-700 pt-3">
                    <p className="leading-relaxed">
                      Hi mate,<br/><br/>
                      Bathroom reno — demo, waterproofing, tiling, vanity, paint. 3-4 weeks. Let me know.<br/><br/>
                      Cheers<br/>
                      Dave
                    </p>
                  </div>
                </div>
              </div>
            </div>
            
            {/* After */}
            <div className="space-y-4">
              <div className="flex items-center space-x-2 mb-4">
                <span className="px-3 py-1 bg-green-500/20 text-green-300 rounded-full text-sm font-medium border border-green-500/30">
                  ✅ After
                </span>
                <span className="text-slate-400 text-sm">ScopeMate generated</span>
              </div>
              <div className="bg-gradient-to-br from-purple-900/20 to-violet-900/20 backdrop-blur-sm border border-purple-500/30 rounded-xl p-6">
                <div className="space-y-4 text-sm">
                  <div className="font-semibold text-white">BATHROOM RENOVATION SCOPE OF WORKS</div>
                  
                  <div>
                    <div className="font-medium text-purple-300 mb-2">INCLUSIONS:</div>
                    <ul className="space-y-1 text-slate-300 text-xs">
                      <li>• Demolition of existing fixtures and fittings</li>
                      <li>• Waterproofing to AS3740 standards</li>
                      <li>• Floor tiling 600x600 porcelain</li>
                      <li>• Wall tiling to 1800mm height</li>
                      <li>• Vanity installation (client supplied)</li>
                      <li>• Tapware connection</li>
                    </ul>
                  </div>
                  
                  <div>
                    <div className="font-medium text-purple-300 mb-2">EXCLUSIONS:</div>
                    <ul className="space-y-1 text-slate-300 text-xs">
                      <li>• Electrical work beyond existing points</li>
                      <li>• Painting beyond bathroom area</li>
                      <li>• Asbestos removal if discovered</li>
                    </ul>
                  </div>
                  
                  <div>
                    <div className="font-medium text-purple-300 mb-2">ALLOWANCES:</div>
                    <ul className="space-y-1 text-slate-300 text-xs">
                      <li>• Tiling: $2,500</li>
                      <li>• Tapware: $1,800</li>
                    </ul>
                  </div>
                  
                  <div className="pt-2 border-t border-slate-700">
                    <div className="text-xs text-slate-400">Timeline: 3-4 weeks | Payment: 30% deposit, progress payments</div>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* How It Works */}
      <section className="py-20 px-4 sm:px-6 lg:px-8">
        <div className="max-w-6xl mx-auto">
          <div className="text-center mb-16">
            <h2 className="text-3xl sm:text-4xl font-bold mb-4">
              How it works
            </h2>
            <p className="text-xl text-slate-300">
              Three simple steps to professional scopes
            </p>
          </div>
          
          <div className="grid md:grid-cols-3 gap-8">
            <div className="text-center space-y-4">
              <div className="w-16 h-16 bg-gradient-to-br from-purple-500 to-violet-500 rounded-full flex items-center justify-center text-2xl font-bold mx-auto">
                1
              </div>
              <h3 className="text-xl font-semibold">Photo site + describe job</h3>
              <p className="text-slate-300">
                Take photos of the work area and add a quick description of what needs doing.
              </p>
            </div>
            
            <div className="text-center space-y-4">
              <div className="w-16 h-16 bg-gradient-to-br from-purple-500 to-violet-500 rounded-full flex items-center justify-center text-2xl font-bold mx-auto">
                2
              </div>
              <h3 className="text-xl font-semibold">AI generates detailed scope</h3>
              <p className="text-slate-300">
                Our AI analyses your photos and creates a comprehensive scope with inclusions, exclusions, and allowances.
              </p>
            </div>
            
            <div className="text-center space-y-4">
              <div className="w-16 h-16 bg-gradient-to-br from-purple-500 to-violet-500 rounded-full flex items-center justify-center text-2xl font-bold mx-auto">
                3
              </div>
              <h3 className="text-xl font-semibold">Review, brand, attach to contract</h3>
              <p className="text-slate-300">
                Review the scope, add your branding, and attach it to your contract. Job done.
              </p>
            </div>
          </div>
        </div>
      </section>

      {/* Features */}
      <section className="py-20 px-4 sm:px-6 lg:px-8 bg-gradient-to-b from-slate-950 to-slate-900/50">
        <div className="max-w-6xl mx-auto">
          <div className="text-center mb-16">
            <h2 className="text-3xl sm:text-4xl font-bold mb-4">
              Everything you need
            </h2>
            <p className="text-xl text-slate-300">
              Built specifically for Australian builders
            </p>
          </div>
          
          <div className="grid md:grid-cols-2 lg:grid-cols-3 gap-8">
            <div className="bg-slate-900/50 backdrop-blur-sm border border-slate-800/50 rounded-xl p-6 hover:border-purple-500/30 transition-all duration-300">
              <div className="text-3xl mb-4">📸</div>
              <h3 className="text-xl font-semibold mb-3">Photo-to-Scope</h3>
              <p className="text-slate-300">
                Upload site photos and get detailed scopes generated automatically.
              </p>
            </div>
            
            <div className="bg-slate-900/50 backdrop-blur-sm border border-slate-800/50 rounded-xl p-6 hover:border-purple-500/30 transition-all duration-300">
              <div className="text-3xl mb-4">📋</div>
              <h3 className="text-xl font-semibold mb-3">Inclusions Library</h3>
              <p className="text-slate-300">
                Pre-built library of common inclusions for different trade types.
              </p>
            </div>
            
            <div className="bg-slate-900/50 backdrop-blur-sm border border-slate-800/50 rounded-xl p-6 hover:border-purple-500/30 transition-all duration-300">
              <div className="text-3xl mb-4">🚫</div>
              <h3 className="text-xl font-semibold mb-3">Exclusion Templates</h3>
              <p className="text-slate-300">
                Smart exclusion templates that protect you from scope creep.
              </p>
            </div>
            
            <div className="bg-slate-900/50 backdrop-blur-sm border border-slate-800/50 rounded-xl p-6 hover:border-purple-500/30 transition-all duration-300">
              <div className="text-3xl mb-4">📄</div>
              <h3 className="text-xl font-semibold mb-3">Contract-Ready Export</h3>
              <p className="text-slate-300">
                Export scopes in formats ready to attach to your contracts.
              </p>
            </div>
            
            <div className="bg-slate-900/50 backdrop-blur-sm border border-slate-800/50 rounded-xl p-6 hover:border-purple-500/30 transition-all duration-300">
              <div className="text-3xl mb-4">👥</div>
              <h3 className="text-xl font-semibold mb-3">Client Portal</h3>
              <p className="text-slate-300">
                Share scopes with clients for approval and sign-off.
              </p>
            </div>
            
            <div className="bg-slate-900/50 backdrop-blur-sm border border-slate-800/50 rounded-xl p-6 hover:border-purple-500/30 transition-all duration-300">
              <div className="text-3xl mb-4">🎨</div>
              <h3 className="text-xl font-semibold mb-3">Your Branding</h3>
              <p className="text-slate-300">
                Add your logo and branding to all generated scopes.
              </p>
            </div>
          </div>
        </div>
      </section>

      {/* Social Proof */}
      <section className="py-20 px-4 sm:px-6 lg:px-8">
        <div className="max-w-4xl mx-auto text-center">
          <div className="space-y-8">
            <div>
              <h2 className="text-3xl sm:text-4xl font-bold mb-4">
                Built for Australian construction
              </h2>
              <p className="text-xl text-slate-300">
                Developed with input from builders, renovators, and project managers across Australia
              </p>
            </div>
            
            <div className="grid md:grid-cols-3 gap-8">
              <div className="space-y-2">
                <div className="text-3xl font-bold text-purple-400">1,200+</div>
                <div className="text-slate-300">Builders on waitlist</div>
              </div>
              <div className="space-y-2">
                <div className="text-3xl font-bold text-purple-400">AS3740</div>
                <div className="text-slate-300">Standards compliant</div>
              </div>
              <div className="space-y-2">
                <div className="text-3xl font-bold text-purple-400">🇦🇺</div>
                <div className="text-slate-300">Australian owned</div>
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* FAQ */}
      <section className="py-20 px-4 sm:px-6 lg:px-8 bg-gradient-to-b from-slate-950 to-slate-900/50">
        <div className="max-w-4xl mx-auto">
          <div className="text-center mb-16">
            <h2 className="text-3xl sm:text-4xl font-bold mb-4">
              Frequently asked questions
            </h2>
          </div>
          
          <div className="space-y-4">
            {[
              {
                question: "How accurate are the AI-generated scopes?",
                answer: "Our AI is trained on thousands of Australian construction projects and industry standards. While we recommend reviewing each scope, most builders find them 90%+ accurate out of the box."
              },
              {
                question: "Can I customise the scopes for my business?",
                answer: "Absolutely. You can add your branding, modify templates, and create custom inclusion/exclusion libraries that match your business practices."
              },
              {
                question: "What types of projects does ScopeMate handle?",
                answer: "We support residential renovations, commercial fit-outs, new builds, and maintenance projects. From bathroom renos to multi-story developments."
              },
              {
                question: "How does early access work?",
                answer: "Early access users get free access during our beta period, priority support, and the ability to influence product development. We'll email you when your spot is ready."
              },
              {
                question: "Is my project data secure?",
                answer: "Yes. All photos and project data are encrypted and stored securely in Australia. We never share your information with third parties."
              }
            ].map((faq, index) => (
              <div key={index} className="bg-slate-900/50 backdrop-blur-sm border border-slate-800/50 rounded-xl overflow-hidden">
                <button
                  onClick={() => setOpenFaq(openFaq === index ? null : index)}
                  className="w-full px-6 py-4 text-left flex items-center justify-between hover:bg-slate-800/30 transition-colors duration-200"
                >
                  <span className="font-medium text-white">{faq.question}</span>
                  <span className={`text-purple-400 transition-transform duration-200 ${openFaq === index ? 'rotate-180' : ''}`}>
                    ↓
                  </span>
                </button>
                {openFaq === index && (
                  <div className="px-6 pb-4">
                    <p className="text-slate-300 leading-relaxed">{faq.answer}</p>
                  </div>
                )}
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* Final CTA */}
      <section className="py-20 px-4 sm:px-6 lg:px-8">
        <div className="max-w-4xl mx-auto text-center space-y-8">
          <div>
            <h2 className="text-3xl sm:text-4xl font-bold mb-4">
              Ready to stop losing money on vague scopes?
            </h2>
            <p className="text-xl text-slate-300 mb-8">
              Join 1,200+ Australian builders getting early access to ScopeMate
            </p>
          </div>
          
          <WaitlistForm showUrgency={true} />
          
          <p className="text-sm text-slate-400">
            Early access is invitation only. We'll email you when your spot is ready.
          </p>
        </div>
      </section>

      {/* Footer */}
      <footer className="border-t border-slate-800/50 py-8 px-4 sm:px-6 lg:px-8">
        <div className="max-w-6xl mx-auto text-center">
          <p className="text-slate-400 text-sm">
            Built by{' '}
            <a 
              href="https://levasolutions.com.au" 
              target="_blank" 
              rel="noopener noreferrer"
              className="text-purple-400 hover:text-purple-300 transition-colors duration-200"
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