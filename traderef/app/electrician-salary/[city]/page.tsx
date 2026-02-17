import { notFound } from 'next/navigation';
import { getSalaryGuide, getAllSalaryGuides } from '@/lib/salary-guides';
import { Metadata } from 'next';

interface PageProps {
  params: {
    city: string;
  };
}

export async function generateMetadata({ params }: PageProps): Promise<Metadata> {
  try {
    const guide = getSalaryGuide(params.city);
    
    return {
      title: `${guide.title} - Electrician Salary Guide 2026`,
      description: guide.description,
      openGraph: {
        title: `${guide.title} - Electrician Salary Guide 2026`,
        description: guide.description,
        type: 'article',
      },
      twitter: {
        card: 'summary_large_image',
        title: `${guide.title} - Electrician Salary Guide 2026`,
        description: guide.description,
      },
    };
  } catch (error) {
    return {
      title: 'Electrician Salary Guide - TradeRef',
      description: 'Comprehensive electrician salary information and career guidance',
    };
  }
}

export async function generateStaticParams() {
  const guides = getAllSalaryGuides();
  return guides.map((guide) => ({
    city: guide.slug,
  }));
}

export default function ElectricianSalaryGuidePage({ params }: PageProps) {
  try {
    const guide = getSalaryGuide(params.city);

    return (
      <div className="min-h-screen bg-gray-50">
        {/* Hero Section */}
        <div className="bg-blue-900 text-white py-16">
          <div className="container mx-auto px-4">
            <h1 className="text-4xl md:text-5xl font-bold mb-4">
              {guide.title}
            </h1>
            <p className="text-xl md:text-2xl text-blue-200 mb-6">
              {guide.description}
            </p>
            <div className="text-sm text-blue-300">
              Last updated: {new Date(guide.lastUpdated).toLocaleDateString()}
            </div>
          </div>
        </div>

        <div className="container mx-auto px-4 py-12">
          <div className="grid md:grid-cols-3 gap-8">
            {/* Main Content */}
            <div className="md:col-span-2">
              {/* Salary Overview */}
              <div className="bg-white rounded-lg shadow-lg p-6 mb-8">
                <h2 className="text-3xl font-bold mb-6 text-gray-800">
                  Average Electrician Salaries in {guide.city}
                </h2>
                <div className="grid sm:grid-cols-2 gap-4">
                  <div className="bg-blue-50 p-4 rounded-lg">
                    <h3 className="font-semibold text-blue-900">Apprentice</h3>
                    <div className="text-2xl font-bold text-blue-700">
                      {guide.averageSalary.apprentice}
                    </div>
                  </div>
                  <div className="bg-green-50 p-4 rounded-lg">
                    <h3 className="font-semibold text-green-900">Journeyman</h3>
                    <div className="text-2xl font-bold text-green-700">
                      {guide.averageSalary.journeyman}
                    </div>
                  </div>
                  <div className="bg-orange-50 p-4 rounded-lg">
                    <h3 className="font-semibold text-orange-900">Master Electrician</h3>
                    <div className="text-2xl font-bold text-orange-700">
                      {guide.averageSalary.master}
                    </div>
                  </div>
                  <div className="bg-purple-50 p-4 rounded-lg">
                    <h3 className="font-semibold text-purple-900">Contractor</h3>
                    <div className="text-2xl font-bold text-purple-700">
                      {guide.averageSalary.contractor}
                    </div>
                  </div>
                </div>
              </div>

              {/* Market Conditions */}
              <div className="bg-white rounded-lg shadow-lg p-6 mb-8">
                <h2 className="text-3xl font-bold mb-6 text-gray-800">
                  Market Conditions
                </h2>
                <div className="grid md:grid-cols-3 gap-4">
                  <div>
                    <h3 className="font-semibold text-gray-700 mb-2">Demand Level</h3>
                    <span className={`inline-block px-3 py-1 rounded-full text-sm font-medium ${
                      guide.marketConditions.demand === 'Very High' ? 'bg-red-100 text-red-800' :
                      guide.marketConditions.demand === 'High' ? 'bg-orange-100 text-orange-800' :
                      guide.marketConditions.demand === 'Moderate' ? 'bg-yellow-100 text-yellow-800' :
                      'bg-gray-100 text-gray-800'
                    }`}>
                      {guide.marketConditions.demand}
                    </span>
                  </div>
                  <div>
                    <h3 className="font-semibold text-gray-700 mb-2">Growth Rate</h3>
                    <div className="text-lg">{guide.marketConditions.growth}</div>
                  </div>
                  <div>
                    <h3 className="font-semibold text-gray-700 mb-2">Cost of Living Index</h3>
                    <div className="text-lg">{guide.costOfLivingIndex}</div>
                  </div>
                </div>
                <div className="mt-4">
                  <h3 className="font-semibold text-gray-700 mb-2">Key Industries</h3>
                  <div className="flex flex-wrap gap-2">
                    {guide.marketConditions.keyIndustries.map((industry, index) => (
                      <span
                        key={index}
                        className="bg-blue-100 text-blue-800 px-3 py-1 rounded-full text-sm"
                      >
                        {industry}
                      </span>
                    ))}
                  </div>
                </div>
              </div>

              {/* Main Content */}
              <div className="bg-white rounded-lg shadow-lg p-6">
                <div 
                  className="prose prose-lg max-w-none"
                  dangerouslySetInnerHTML={{ __html: guide.content }}
                />
              </div>
            </div>

            {/* Sidebar */}
            <div className="space-y-6">
              {/* Major Employers */}
              <div className="bg-white rounded-lg shadow-lg p-6">
                <h3 className="text-xl font-bold mb-4 text-gray-800">
                  Major Employers
                </h3>
                <ul className="space-y-2">
                  {guide.majorEmployers.map((employer, index) => (
                    <li key={index} className="text-gray-600">
                      • {employer}
                    </li>
                  ))}
                </ul>
              </div>

              {/* Training Programs */}
              <div className="bg-white rounded-lg shadow-lg p-6">
                <h3 className="text-xl font-bold mb-4 text-gray-800">
                  Training & Apprenticeships
                </h3>
                <ul className="space-y-2">
                  {guide.trainingPrograms.map((program, index) => (
                    <li key={index} className="text-gray-600">
                      • {program}
                    </li>
                  ))}
                </ul>
              </div>

              {/* Union Information */}
              <div className="bg-white rounded-lg shadow-lg p-6">
                <h3 className="text-xl font-bold mb-4 text-gray-800">
                  Union Presence
                </h3>
                <div className="space-y-2">
                  <div>
                    <span className="font-medium">Active:</span>{' '}
                    <span className={`font-medium ${
                      guide.unionPresence.active ? 'text-green-600' : 'text-red-600'
                    }`}>
                      {guide.unionPresence.active ? 'Yes' : 'No'}
                    </span>
                  </div>
                  {guide.unionPresence.active && (
                    <>
                      <div>
                        <span className="font-medium">Main Union:</span>{' '}
                        {guide.unionPresence.mainUnion}
                      </div>
                      <div>
                        <span className="font-medium">Coverage:</span>{' '}
                        {guide.unionPresence.coverage}
                      </div>
                    </>
                  )}
                </div>
              </div>

              {/* Licensing */}
              <div className="bg-white rounded-lg shadow-lg p-6">
                <h3 className="text-xl font-bold mb-4 text-gray-800">
                  Licensing Requirements
                </h3>
                <div className="space-y-3">
                  <div>
                    <span className="font-medium">Required:</span>{' '}
                    <span className={`font-medium ${
                      guide.licensing.required ? 'text-red-600' : 'text-green-600'
                    }`}>
                      {guide.licensing.required ? 'Yes' : 'No'}
                    </span>
                  </div>
                  {guide.licensing.required && (
                    <>
                      <div>
                        <span className="font-medium">Authority:</span>{' '}
                        {guide.licensing.authority}
                      </div>
                      <div>
                        <span className="font-medium">Requirements:</span>
                        <ul className="mt-1 ml-4">
                          {guide.licensing.requirements.map((req, index) => (
                            <li key={index} className="text-gray-600">
                              • {req}
                            </li>
                          ))}
                        </ul>
                      </div>
                    </>
                  )}
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    );
  } catch (error) {
    notFound();
  }
}