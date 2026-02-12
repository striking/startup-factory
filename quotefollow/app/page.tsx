'use client'

import { useState } from 'react'
import { Geist } from 'next/font/google'
import { Analytics } from '@vercel/analytics/react'

const geist = Geist({ subsets: ['latin'] })

export default function Page() {
  const [openFaq, setOpenFaq] = useState<number | null>(null)

  const toggleFaq = (index: number) => {
    setOpenFaq(openFaq === index ? null : index)
  }

  return (
    <div className={`${geist.className} min-h-screen bg-slate-950 text-white`}>
      {/* Hero Section */}
      <section className="relative overflow-hidden">
        <div className="absolute inset-0 bg-gradient-to-br from-blue-500/10 via-transparent to-purple-500/10"></div>
        <div className="relative max-w-6xl mx-auto px-4 sm:px-6 lg:px-8 pt-16 pb-24">
          <div className="text-center">
            <div className="inline-flex items-center px-4 py-2 rounded-full bg-blue-500/10 border border-blue-500/20 backdrop-blur-sm mb-8">
              <span className="text-blue-400 text-sm font-medium">🚀 Invitation Only</span>
            </div>
            
            <h1 className="text-4xl sm:text-5xl lg:text-6xl font-bold mb-6 bg-gradient-to-r from-white via-slate-200 to-slate-400 bg-clip-text text-transparent">
              We chase your quotes for you
            </h1>
            
            <p className="text-xl sm:text-2xl text-slate-300 mb-8 max-w-3xl mx-auto leading-relaxed">
              Done-for-you follow-up service. No dashboards. Set up in 24 hours.
            </p>

            <div className="mb-8">
              <a
                href="https://levasolutions.com.au/book"
                target="_blank"
                rel="noopener noreferrer"
                className="inline-flex items-center justify-center px-8 py-4 bg-gradient-to-r from-blue-500 to-blue-600 hover:from-blue-600 hover:to-blue-700 rounded-lg font-semibold transition-all transform hover:scale-105"
              >
                Book 15-min Setup Call
              </a>
            </div>

            <div className="flex items-center justify-center gap-2 text-slate-400">
              <div className="w-2 h-2 rounded-full bg-green-400"></div>
              <span className="text-sm">Founding Offer now open</span>
            </div>
          </div>
        </div>
      </section>

      {/* Problem Section */}
      <section className="py-24 bg-slate-900/50">
        <div className="max-w-6xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="text-center mb-16">
            <h2 className="text-3xl sm:text-4xl font-bold mb-4">Sound familiar?</h2>
            <p className="text-xl text-slate-300">These are the stories we hear every day</p>
          </div>

          <div className="grid md:grid-cols-3 gap-8">
            <div className="bg-slate-800/30 backdrop-blur-sm border border-slate-700/50 rounded-xl p-6 hover:border-slate-600/50 transition-all">
              <div className="text-4xl mb-4">😤</div>
              <blockquote className="text-slate-300 italic mb-4">
                "Sent 15 quotes last month. Followed up on 3. The other 12? Who knows."
              </blockquote>
              <div className="text-sm text-slate-400">— Plumber, Sydney</div>
            </div>

            <div className="bg-slate-800/30 backdrop-blur-sm border border-slate-700/50 rounded-xl p-6 hover:border-slate-600/50 transition-all">
              <div className="text-4xl mb-4">💸</div>
              <blockquote className="text-slate-300 italic mb-4">
                "Customer went with someone else because I took 4 days to follow up."
              </blockquote>
              <div className="text-sm text-slate-400">— Electrician, Melbourne</div>
            </div>

            <div className="bg-slate-800/30 backdrop-blur-sm border border-slate-700/50 rounded-xl p-6 hover:border-slate-600/50 transition-all">
              <div className="text-4xl mb-4">⏰</div>
              <blockquote className="text-slate-300 italic mb-4">
                "Should follow up but on the tools at 6am. By the time I remember, it's been two weeks."
              </blockquote>
              <div className="text-sm text-slate-400">— Builder, Brisbane</div>
            </div>
          </div>
        </div>
      </section>

      {/* Show Don't Tell Section */}
      <section className="py-24">
        <div className="max-w-6xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="text-center mb-16">
            <h2 className="text-3xl sm:text-4xl font-bold mb-4">Here's what changes</h2>
            <p className="text-xl text-slate-300">Same quote. Different outcome.</p>
          </div>

          <div className="space-y-12">
            {/* Without QuoteFollow */}
            <div className="bg-red-500/5 border border-red-500/20 rounded-xl p-8">
              <div className="flex items-center gap-3 mb-6">
                <div className="w-8 h-8 rounded-full bg-red-500 flex items-center justify-center">
                  <span className="text-white text-lg">✕</span>
                </div>
                <h3 className="text-xl font-semibold text-red-400">Without QuoteFollow</h3>
              </div>
              
              <div className="flex flex-col sm:flex-row items-start sm:items-center gap-4 overflow-x-auto">
                <div className="flex-shrink-0 bg-slate-800 rounded-lg p-4 min-w-[200px]">
                  <div className="text-sm text-slate-400 mb-1">Monday</div>
                  <div className="text-white">Quote sent to Sarah</div>
                  <div className="text-xs text-slate-500 mt-1">Bathroom renovation - $8,500</div>
                </div>
                
                <div className="hidden sm:block text-slate-600">→</div>
                
                <div className="flex-shrink-0 bg-slate-800 rounded-lg p-4 min-w-[200px] opacity-50">
                  <div className="text-sm text-slate-400 mb-1">Tuesday - Wednesday</div>
                  <div className="text-slate-400">Silence...</div>
                  <div className="text-xs text-slate-500 mt-1">Too busy to follow up</div>
                </div>
                
                <div className="hidden sm:block text-slate-600">→</div>
                
                <div className="flex-shrink-0 bg-red-900/30 border border-red-500/30 rounded-lg p-4 min-w-[200px]">
                  <div className="text-sm text-red-400 mb-1">Thursday</div>
                  <div className="text-red-300">Sarah books competitor</div>
                  <div className="text-xs text-red-500 mt-1">They followed up Wednesday</div>
                </div>
                
                <div className="hidden sm:block text-slate-600">→</div>
                
                <div className="flex-shrink-0 bg-slate-800 rounded-lg p-4 min-w-[200px]">
                  <div className="text-sm text-slate-400 mb-1">Friday</div>
                  <div className="text-slate-300">You finally call</div>
                  <div className="text-xs text-slate-500 mt-1">"Oh, we went with someone else"</div>
                </div>
              </div>
            </div>

            {/* With QuoteFollow */}
            <div className="bg-green-500/5 border border-green-500/20 rounded-xl p-8">
              <div className="flex items-center gap-3 mb-6">
                <div className="w-8 h-8 rounded-full bg-green-500 flex items-center justify-center">
                  <span className="text-white text-lg">✓</span>
                </div>
                <h3 className="text-xl font-semibold text-green-400">With QuoteFollow</h3>
              </div>
              
              <div className="flex flex-col sm:flex-row items-start sm:items-center gap-4 overflow-x-auto">
                <div className="flex-shrink-0 bg-slate-800 rounded-lg p-4 min-w-[200px]">
                  <div className="text-sm text-slate-400 mb-1">Monday</div>
                  <div className="text-white">Quote sent to Sarah</div>
                  <div className="text-xs text-slate-500 mt-1">Bathroom renovation - $8,500</div>
                </div>
                
                <div className="hidden sm:block text-slate-600">→</div>
                
                <div className="flex-shrink-0 bg-blue-900/30 border border-blue-500/30 rounded-lg p-4 min-w-[200px]">
                  <div className="text-sm text-blue-400 mb-1">Wednesday</div>
                  <div className="text-blue-300">Auto follow-up sent</div>
                  <div className="text-xs text-blue-500 mt-1">"Hi Sarah, checking in on bathroom quote"</div>
                </div>
                
                <div className="hidden sm:block text-slate-600">→</div>
                
                <div className="flex-shrink-0 bg-green-900/30 border border-green-500/30 rounded-lg p-4 min-w-[200px]">
                  <div className="text-sm text-green-400 mb-1">Thursday</div>
                  <div className="text-green-300">Sarah replies</div>
                  <div className="text-xs text-green-500 mt-1">"Yes, let's go ahead!"</div>
                </div>
                
                <div className="hidden sm:block text-slate-600">→</div>
                
                <div className="flex-shrink-0 bg-green-900/30 border border-green-500/30 rounded-lg p-4 min-w-[200px]">
                  <div className="text-sm text-green-400 mb-1">Result</div>
                  <div className="text-green-300">Job booked</div>
                  <div className="text-xs text-green-500 mt-1">$8,500 secured</div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* How It Works */}
      <section className="py-24 bg-slate-900/50">
        <div className="max-w-6xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="text-center mb-16">
            <h2 className="text-3xl sm:text-4xl font-bold mb-4">How it works</h2>
            <p className="text-xl text-slate-300">Set it once. Forget about it. Win more jobs.</p>
          </div>

          <div className="grid md:grid-cols-3 gap-8">
            <div className="text-center">
              <div className="w-16 h-16 bg-gradient-to-r from-blue-500 to-blue-600 rounded-full flex items-center justify-center text-2xl font-bold mb-6 mx-auto">
                1
              </div>
              <h3 className="text-xl font-semibold mb-4">Send quote as normal</h3>
              <p className="text-slate-300">Use your existing process. Email, text, or hand-deliver your quotes like you always do.</p>
            </div>

            <div className="text-center">
              <div className="w-16 h-16 bg-gradient-to-r from-blue-500 to-blue-600 rounded-full flex items-center justify-center text-2xl font-bold mb-6 mx-auto">
                2
              </div>
              <h3 className="text-xl font-semibold mb-4">AI follows up via SMS + email</h3>
              <p className="text-slate-300">Smart timing ensures your follow-ups feel natural and professional, not pushy.</p>
            </div>

            <div className="text-center">
              <div className="w-16 h-16 bg-gradient-to-r from-blue-500 to-blue-600 rounded-full flex items-center justify-center text-2xl font-bold mb-6 mx-auto">
                3
              </div>
              <h3 className="text-xl font-semibold mb-4">Get notified when ready to book</h3>
              <p className="text-slate-300">Instant alerts when customers respond. Strike while the iron's hot.</p>
            </div>
          </div>
        </div>
      </section>

      {/* Features */}
      <section className="py-24">
        <div className="max-w-6xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="text-center mb-16">
            <h2 className="text-3xl sm:text-4xl font-bold mb-4">Everything you need</h2>
            <p className="text-xl text-slate-300">Built specifically for Australian tradies</p>
          </div>

          <div className="grid sm:grid-cols-2 lg:grid-cols-3 gap-8">
            <div className="bg-slate-800/30 backdrop-blur-sm border border-slate-700/50 rounded-xl p-6 hover:border-slate-600/50 transition-all">
              <div className="text-3xl mb-4">🤖</div>
              <h3 className="text-xl font-semibold mb-3">Auto Follow-Up</h3>
              <p className="text-slate-300">Intelligent follow-ups that sound like you wrote them. No robotic messages.</p>
            </div>

            <div className="bg-slate-800/30 backdrop-blur-sm border border-slate-700/50 rounded-xl p-6 hover:border-slate-600/50 transition-all">
              <div className="text-3xl mb-4">📱</div>
              <h3 className="text-xl font-semibold mb-3">SMS + Email</h3>
              <p className="text-slate-300">Reach customers where they are. Multi-channel follow-ups increase response rates.</p>
            </div>

            <div className="bg-slate-800/30 backdrop-blur-sm border border-slate-700/50 rounded-xl p-6 hover:border-slate-600/50 transition-all">
              <div className="text-3xl mb-4">⏰</div>
              <h3 className="text-xl font-semibold mb-3">Smart Timing</h3>
              <p className="text-slate-300">Follows up at the perfect moment. Not too early, not too late.</p>
            </div>

            <div className="bg-slate-800/30 backdrop-blur-sm border border-slate-700/50 rounded-xl p-6 hover:border-slate-600/50 transition-all">
              <div className="text-3xl mb-4">📊</div>
              <h3 className="text-xl font-semibold mb-3">Quote Tracking</h3>
              <p className="text-slate-300">See which quotes are hot, cold, or ready to close. Never lose track again.</p>
            </div>

            <div className="bg-slate-800/30 backdrop-blur-sm border border-slate-700/50 rounded-xl p-6 hover:border-slate-600/50 transition-all">
              <div className="text-3xl mb-4">📈</div>
              <h3 className="text-xl font-semibold mb-3">Win/Loss Analytics</h3>
              <p className="text-slate-300">Understand what's working. Improve your quote-to-job conversion rate.</p>
            </div>

            <div className="bg-slate-800/30 backdrop-blur-sm border border-slate-700/50 rounded-xl p-6 hover:border-slate-600/50 transition-all">
              <div className="text-3xl mb-4">🔗</div>
              <h3 className="text-xl font-semibold mb-3">CRM Sync</h3>
              <p className="text-slate-300">Works with your existing tools. No need to change your workflow.</p>
            </div>
          </div>
        </div>
      </section>

      {/* Social Proof */}
      <section className="py-24 bg-slate-900/50">
        <div className="max-w-4xl mx-auto px-4 sm:px-6 lg:px-8 text-center">
          <div className="bg-slate-800/30 backdrop-blur-sm border border-slate-700/50 rounded-xl p-8">
            <div className="text-4xl mb-6">🇦🇺</div>
            <h2 className="text-2xl font-bold mb-4">Built for Australian construction</h2>
            <p className="text-lg text-slate-300 mb-6">
              We understand the unique challenges of running a trade business in Australia. 
              From compliance requirements to customer expectations, QuoteFollow is designed 
              with local tradies in mind.
            </p>
            <div className="flex flex-wrap justify-center gap-4">
              <span className="px-3 py-1 bg-blue-500/20 text-blue-300 rounded-full text-sm">Australian English</span>
              <span className="px-3 py-1 bg-blue-500/20 text-blue-300 rounded-full text-sm">Local Business Hours</span>
              <span className="px-3 py-1 bg-blue-500/20 text-blue-300 rounded-full text-sm">Industry Compliant</span>
              <span className="px-3 py-1 bg-blue-500/20 text-blue-300 rounded-full text-sm">Tradie-Tested</span>
            </div>
          </div>
        </div>
      </section>

      {/* FAQ */}
      <section className="py-24">
        <div className="max-w-4xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="text-center mb-16">
            <h2 className="text-3xl sm:text-4xl font-bold mb-4">Common questions</h2>
            <p className="text-xl text-slate-300">Everything you need to know</p>
          </div>

          <div className="space-y-4">
            {[
              {
                question: "How does QuoteFollow know when I've sent a quote?",
                answer: "You can forward quotes to QuoteFollow, or we integrate with popular quoting tools. We're also building direct integrations with major trade software platforms."
              },
              {
                question: "Will customers know it's automated?",
                answer: "No. Our AI writes follow-ups that sound natural and personal. Customers think you're just really good at staying in touch."
              },
              {
                question: "What if a customer replies to a follow-up?",
                answer: "You get an instant notification. All replies come straight to you, so you can jump in and close the deal."
              },
              {
                question: "Can I customise the follow-up messages?",
                answer: "Absolutely. You can set your tone, add your business details, and even create templates for different types of jobs."
              },
              {
                question: "When will QuoteFollow be available?",
                answer: "We're launching in early 2025. Waitlist members get first access and special launch pricing."
              }
            ].map((faq, index) => (
              <div key={index} className="bg-slate-800/30 backdrop-blur-sm border border-slate-700/50 rounded-xl overflow-hidden">
                <button
                  onClick={() => toggleFaq(index)}
                  className="w-full px-6 py-4 text-left flex items-center justify-between hover:bg-slate-700/30 transition-all"
                >
                  <span className="font-semibold">{faq.question}</span>
                  <span className={`transform transition-transform ${openFaq === index ? 'rotate-180' : ''}`}>
                    ↓
                  </span>
                </button>
                {openFaq === index && (
                  <div className="px-6 pb-4">
                    <p className="text-slate-300">{faq.answer}</p>
                  </div>
                )}
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* Final CTA */}
      <section className="py-24 bg-gradient-to-r from-blue-500/10 via-purple-500/10 to-blue-500/10">
        <div className="max-w-4xl mx-auto px-4 sm:px-6 lg:px-8 text-center">
          <h2 className="text-3xl sm:text-4xl font-bold mb-4">Ready to stop chasing quotes manually?</h2>
          <p className="text-xl text-slate-300 mb-8">
            Book a quick setup call and we’ll show you how QuoteFollow works for your business.
          </p>

          <div className="mb-8">
            <a
              href="https://levasolutions.com.au/book"
              target="_blank"
              rel="noopener noreferrer"
              className="inline-flex items-center justify-center px-8 py-4 bg-gradient-to-r from-blue-500 to-blue-600 hover:from-blue-600 hover:to-blue-700 rounded-lg font-semibold transition-all transform hover:scale-105"
            >
              Book 15-min Setup Call
            </a>
          </div>

          <div className="text-sm text-slate-400">
            ⚡ Founding Offer — limited onboarding spots each week
          </div>
        </div>
      </section>

      {/* Footer */}
      <footer className="py-8 border-t border-slate-800">
        <div className="max-w-6xl mx-auto px-4 sm:px-6 lg:px-8 text-center">
          <p className="text-slate-400">
            Built by{' '}
            <a 
              href="https://levasolutions.com.au" 
              target="_blank" 
              rel="noopener noreferrer"
              className="text-blue-400 hover:text-blue-300 transition-colors"
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