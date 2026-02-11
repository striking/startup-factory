export const config = {
  // ============================================
  // PRODUCT CONFIG — Change these values only
  // ============================================
  name: "TextTime",
  tagline: "Time tracking that works like texting",
  description:
    "Your crew texts in when they start. Texts out when they finish. AI builds the timesheet. No app to download. No training needed. Just SMS.",
  accentColor: "#3B82F6",
  domain: "texttime.grapl.ai",

  painPoints: [
    {
      emoji: "📋",
      title: "Timesheets Nobody Fills In",
      desc: "Paper timesheets get lost. Apps get ignored. You end up chasing hours every Friday afternoon.",
    },
    {
      emoji: "📱",
      title: "Too Many Apps Already",
      desc: "Your crew doesn't want another app. They barely use the ones they have. SMS works because everyone already knows how.",
    },
    {
      emoji: "💸",
      title: "Payroll Guesswork",
      desc: "Without accurate hours, you're either overpaying or underpaying. Both cost you money and trust.",
    },
  ],

  solution: {
    title: "Time tracking without the tracking",
    desc: 'Your workers text "start" when they arrive and "stop" when they leave. That\'s it. AI handles the rest — calculates hours, flags overtime, builds timesheets, and exports to payroll. No logins. No apps. No friction.',
  },

  features: [
    {
      title: "SMS Clock In/Out",
      desc: "Workers text from their own phone. No app download, no training, no excuses.",
    },
    {
      title: "GPS Verification",
      desc: "Optional location check confirms they're actually on-site when they clock in.",
    },
    {
      title: "Auto Timesheets",
      desc: "AI builds accurate timesheets from SMS data. Ready for payroll every week.",
    },
    {
      title: "Payroll Export",
      desc: "One-click export to Xero, MYOB, QuickBooks, or CSV for any system.",
    },
    {
      title: "Team Dashboard",
      desc: "See who's on-site right now, who's late, and who hasn't clocked in.",
    },
    {
      title: "Overtime Alerts",
      desc: "Get notified before overtime kicks in so you can manage costs proactively.",
    },
  ],

  howItWorks: [
    {
      step: "1",
      title: "Workers Text In",
      desc: 'They send "start" to your TextTime number when they arrive on-site.',
    },
    {
      step: "2",
      title: "AI Tracks Everything",
      desc: "Hours calculated, breaks detected, overtime flagged — all automatic.",
    },
    {
      step: "3",
      title: "Export to Payroll",
      desc: "Accurate timesheets ready every week. One click to your payroll system.",
    },
  ],

  pricing: {
    free: {
      name: "Free",
      price: "$0",
      period: "forever",
      features: [
        "5 workers",
        "100 SMS/month",
        "Basic timesheets",
        "CSV export",
      ],
    },
    pro: {
      name: "Pro",
      price: "$49",
      period: "/month",
      features: [
        "25 workers",
        "Unlimited SMS",
        "GPS verification",
        "Payroll integrations",
        "Team dashboard",
        "Overtime alerts",
      ],
    },
    business: {
      name: "Business",
      price: "$99",
      period: "/month",
      features: [
        "Unlimited workers",
        "Everything in Pro",
        "Multi-site management",
        "Custom reports",
        "API access",
        "Priority support",
      ],
    },
  },

  faq: [
    {
      q: "Do my workers need to download an app?",
      a: "No. TextTime works entirely over SMS. If they can send a text message, they can use TextTime. No app, no login, no training.",
    },
    {
      q: "What if someone forgets to clock in?",
      a: "TextTime sends a gentle SMS reminder if a worker hasn't clocked in by their usual start time. Supervisors can also add manual entries.",
    },
    {
      q: "How accurate is the GPS verification?",
      a: "GPS verification uses the location data from the SMS to confirm the worker is within a configurable radius of the job site. Typically accurate to within 50 meters.",
    },
    {
      q: "Can I try it before paying?",
      a: "Yes — the Free plan includes 5 workers and 100 SMS per month with no time limit. No credit card required.",
    },
    {
      q: "What payroll systems do you integrate with?",
      a: "We export to Xero, MYOB, QuickBooks, and any system that accepts CSV. More integrations are added based on demand.",
    },
  ],

  // Waitlist / analytics
  waitlistAction: "", // Google Sheets URL or API endpoint
  analyticsId: "", // Umami site ID
  analyticsUrl: "", // Umami script URL e.g. https://analytics.grapl.ai/script.js
};
