import { useState } from 'react'
import { sections } from './data/sections'
import { overviewContent, features } from './data/overview'
import { architectureContent } from './data/architecture'
import { dataModels } from './data/dataModels'
import { recordingModule, noteModule, storageModule, supabaseModule, aiModule, emailModule, uiModule } from './data/modules'
import { timeline } from './data/timeline'
import { bestPractices } from './data/bestPractices'
import { supabaseSchema } from './data/supabaseSchema'
import { edgeFunctions, monitoring } from './data/monitoring'
import './App.css'

function App() {
  const [activeSection, setActiveSection] = useState('overview')

  return (
    <div className="min-h-screen bg-gray-50">
      <header className="bg-blue-600 text-white py-6 shadow-md">
        <div className="container mx-auto px-4">
          <h1 className="text-3xl font-bold">TabletNotes MVP Implementation Plan</h1>
          <p className="mt-2 text-blue-100">A comprehensive roadmap for building the sermon note-taking app</p>
        </div>
      </header>

      <div className="container mx-auto px-4 py-8 flex flex-col md:flex-row gap-8">
        {/* Sidebar Navigation */}
        <aside className="md:w-1/4 bg-white p-4 rounded-lg shadow-md h-fit sticky top-4">
          <nav>
            <ul className="space-y-1">
              {sections.map((section) => (
                <li key={section.id}>
                  <button
                    onClick={() => setActiveSection(section.id)}
                    className={`w-full text-left px-4 py-2 rounded-md transition-colors ${
                      activeSection === section.id
                        ? 'bg-blue-100 text-blue-700 font-medium'
                        : 'hover:bg-gray-100'
                    }`}
                  >
                    {section.title}
                  </button>
                </li>
              ))}
            </ul>
          </nav>
        </aside>

        {/* Main Content */}
        <main className="md:w-3/4 bg-white p-6 rounded-lg shadow-md">
          {activeSection === 'overview' && (
            <section>
              <h2 className="text-2xl font-bold text-gray-800 mb-4">{overviewContent.title}</h2>
              <p className="text-gray-700 mb-8">{overviewContent.description}</p>
              
              <h3 className="text-xl font-semibold text-gray-800 mb-4">Core MVP Features</h3>
              <div className="grid grid-cols-1 md:grid-cols-2 gap-4 mb-8">
                {features.map((feature) => (
                  <div key={feature.id} className="border border-gray-200 rounded-lg p-4 hover:shadow-md transition-shadow">
                    <h4 className="text-lg font-medium text-blue-600 mb-2">{feature.title}</h4>
                    <p className="text-gray-600">{feature.description}</p>
                  </div>
                ))}
              </div>
            </section>
          )}

          {activeSection === 'architecture' && (
            <section>
              <h2 className="text-2xl font-bold text-gray-800 mb-4">Technical Architecture</h2>
              
              <h3 className="text-xl font-semibold text-gray-800 mb-4">System Components</h3>
              <div className="bg-gray-100 p-4 rounded-lg mb-6 overflow-x-auto">
                <pre className="whitespace-pre text-sm text-gray-800">{architectureContent.diagram}</pre>
              </div>
              
              <h3 className="text-xl font-semibold text-gray-800 mb-4">Data Flow</h3>
              <ol className="list-decimal pl-5 space-y-2 mb-6">
                {architectureContent.dataFlow.map((step, index) => (
                  <li key={index} className="text-gray-700">{step}</li>
                ))}
              </ol>
            </section>
          )}

          {activeSection === 'data-models' && (
            <section>
              <h2 className="text-2xl font-bold text-gray-800 mb-4">Core Data Models</h2>
              <p className="text-gray-700 mb-6">The following Swift data structures define the core models for the TabletNotes app:</p>
              
              <div className="space-y-6">
                {dataModels.map((model) => (
                  <div key={model.name} className="border border-gray-200 rounded-lg overflow-hidden">
                    <div className="bg-gray-50 px-4 py-2 border-b border-gray-200">
                      <h3 className="font-medium text-gray-800">{model.name}</h3>
                    </div>
                    <div className="p-4 bg-gray-100 overflow-x-auto">
                      <pre className="text-sm text-gray-800">{model.code}</pre>
                    </div>
                  </div>
                ))}
              </div>
            </section>
          )}

          {activeSection === 'recording' && (
            <section>
              <h2 className="text-2xl font-bold text-gray-800 mb-4">{recordingModule.title}</h2>
              
              <h3 className="text-xl font-semibold text-gray-800 mb-4">Implementation Tasks</h3>
              <ul className="list-disc pl-5 space-y-2 mb-6">
                {recordingModule.tasks.map((task, index) => (
                  <li key={index} className="text-gray-700">{task}</li>
                ))}
              </ul>
              
              <h3 className="text-xl font-semibold text-gray-800 mb-4">Sample Implementation</h3>
              <div className="bg-gray-100 p-4 rounded-lg overflow-x-auto">
                <pre className="text-sm text-gray-800">{recordingModule.code}</pre>
              </div>
            </section>
          )}

          {activeSection === 'note-taking' && (
            <section>
              <h2 className="text-2xl font-bold text-gray-800 mb-4">{noteModule.title}</h2>
              
              <h3 className="text-xl font-semibold text-gray-800 mb-4">Implementation Tasks</h3>
              <ul className="list-disc pl-5 space-y-2 mb-6">
                {noteModule.tasks.map((task, index) => (
                  <li key={index} className="text-gray-700">{task}</li>
                ))}
              </ul>
              
              <h3 className="text-xl font-semibold text-gray-800 mb-4">Sample Implementation</h3>
              <div className="bg-gray-100 p-4 rounded-lg overflow-x-auto">
                <pre className="text-sm text-gray-800">{noteModule.code}</pre>
              </div>
            </section>
          )}

          {activeSection === 'storage' && (
            <section>
              <h2 className="text-2xl font-bold text-gray-800 mb-4">{storageModule.title}</h2>
              
              <h3 className="text-xl font-semibold text-gray-800 mb-4">Implementation Tasks</h3>
              <ul className="list-disc pl-5 space-y-2 mb-6">
                {storageModule.tasks.map((task, index) => (
                  <li key={index} className="text-gray-700">{task}</li>
                ))}
              </ul>
              
              <h3 className="text-xl font-semibold text-gray-800 mb-4">Sample Implementation</h3>
              <div className="bg-gray-100 p-4 rounded-lg overflow-x-auto">
                <pre className="text-sm text-gray-800">{storageModule.code}</pre>
              </div>
            </section>
          )}

          {activeSection === 'supabase' && (
            <section>
              <h2 className="text-2xl font-bold text-gray-800 mb-4">{supabaseModule.title}</h2>
              
              <h3 className="text-xl font-semibold text-gray-800 mb-4">Implementation Tasks</h3>
              <ul className="list-disc pl-5 space-y-2 mb-6">
                {supabaseModule.tasks.map((task, index) => (
                  <li key={index} className="text-gray-700">{task}</li>
                ))}
              </ul>
              
              <h3 className="text-xl font-semibold text-gray-800 mb-4">Sample Implementation</h3>
              <div className="bg-gray-100 p-4 rounded-lg overflow-x-auto">
                <pre className="text-sm text-gray-800">{supabaseModule.code}</pre>
              </div>
            </section>
          )}

          {activeSection === 'summarization' && (
            <section>
              <h2 className="text-2xl font-bold text-gray-800 mb-4">{aiModule.title}</h2>
              
              <h3 className="text-xl font-semibold text-gray-800 mb-4">Implementation Tasks</h3>
              <ul className="list-disc pl-5 space-y-2 mb-6">
                {aiModule.tasks.map((task, index) => (
                  <li key={index} className="text-gray-700">{task}</li>
                ))}
              </ul>
              
              <h3 className="text-xl font-semibold text-gray-800 mb-4">Sample Implementation</h3>
              <div className="bg-gray-100 p-4 rounded-lg overflow-x-auto">
                <pre className="text-sm text-gray-800">{aiModule.code}</pre>
              </div>
            </section>
          )}

          {activeSection === 'notifications' && (
            <section>
              <h2 className="text-2xl font-bold text-gray-800 mb-4">{emailModule.title}</h2>
              
              <h3 className="text-xl font-semibold text-gray-800 mb-4">Implementation Tasks</h3>
              <ul className="list-disc pl-5 space-y-2 mb-6">
                {emailModule.tasks.map((task, index) => (
                  <li key={index} className="text-gray-700">{task}</li>
                ))}
              </ul>
              
              <h3 className="text-xl font-semibold text-gray-800 mb-4">Sample Implementation</h3>
              <div className="bg-gray-100 p-4 rounded-lg overflow-x-auto">
                <pre className="text-sm text-gray-800">{emailModule.code}</pre>
              </div>
            </section>
          )}

          {activeSection === 'ui' && (
            <section>
              <h2 className="text-2xl font-bold text-gray-800 mb-4">{uiModule.title}</h2>
              
              <h3 className="text-xl font-semibold text-gray-800 mb-4">Implementation Tasks</h3>
              <ul className="list-disc pl-5 space-y-2 mb-6">
                {uiModule.tasks.map((task, index) => (
                  <li key={index} className="text-gray-700">{task}</li>
                ))}
              </ul>
              
              <h3 className="text-xl font-semibold text-gray-800 mb-4">Sample Implementation</h3>
              <div className="bg-gray-100 p-4 rounded-lg overflow-x-auto">
                <pre className="text-sm text-gray-800">{uiModule.code}</pre>
              </div>
            </section>
          )}

          {activeSection === 'timeline' && (
            <section>
              <h2 className="text-2xl font-bold text-gray-800 mb-4">Implementation Timeline</h2>
              <p className="text-gray-700 mb-6">The following 6-week timeline outlines the development roadmap for the TabletNotes MVP:</p>
              
              <div className="space-y-6">
                {timeline.map((week) => (
                  <div key={week.week} className="border border-gray-200 rounded-lg overflow-hidden">
                    <div className="bg-blue-50 px-4 py-2 border-b border-gray-200">
                      <h3 className="font-medium text-blue-800">Week {week.week}: {week.title}</h3>
                    </div>
                    <div className="p-4">
                      <ul className="list-disc pl-5 space-y-1">
                        {week.tasks.map((task, index) => (
                          <li key={index} className="text-gray-700">{task}</li>
                        ))}
                      </ul>
                    </div>
                  </div>
                ))}
              </div>
            </section>
          )}

          {activeSection === 'best-practices' && (
            <section>
              <h2 className="text-2xl font-bold text-gray-800 mb-4">Best Practices</h2>
              <p className="text-gray-700 mb-6">The following best practices should be followed during implementation:</p>
              
              <div className="space-y-6">
                {bestPractices.map((practice) => (
                  <div key={practice.category} className="border border-gray-200 rounded-lg overflow-hidden">
                    <div className="bg-green-50 px-4 py-2 border-b border-gray-200">
                      <h3 className="font-medium text-green-800">{practice.category}</h3>
                    </div>
                    <div className="p-4">
                      <ul className="list-disc pl-5 space-y-1">
                        {practice.practices.map((item, index) => (
                          <li key={index} className="text-gray-700">{item}</li>
                        ))}
                      </ul>
                    </div>
                  </div>
                ))}
              </div>
            </section>
          )}

          {activeSection === 'supabase-schema' && (
            <section>
              <h2 className="text-2xl font-bold text-gray-800 mb-4">Supabase Schema</h2>
              <p className="text-gray-700 mb-6">The following SQL defines the database schema for the TabletNotes app:</p>
              
              <div className="space-y-6">
                {supabaseSchema.map((schema) => (
                  <div key={schema.tableName} className="border border-gray-200 rounded-lg overflow-hidden">
                    <div className="bg-purple-50 px-4 py-2 border-b border-gray-200">
                      <h3 className="font-medium text-purple-800">{schema.tableName}</h3>
                    </div>
                    <div className="p-4 bg-gray-100 overflow-x-auto">
                      <pre className="text-sm text-gray-800">{schema.sql}</pre>
                    </div>
                  </div>
                ))}
              </div>
            </section>
          )}

          {activeSection === 'edge-functions' && (
            <section>
              <h2 className="text-2xl font-bold text-gray-800 mb-4">Edge Functions</h2>
              <p className="text-gray-700 mb-6">The following Edge Functions will be implemented in Supabase:</p>
              
              <div className="space-y-4 mb-8">
                {edgeFunctions.map((func) => (
                  <div key={func.name} className="border border-gray-200 rounded-lg p-4">
                    <h3 className="font-medium text-gray-800 mb-2">{func.name}</h3>
                    <p className="text-gray-600">{func.description}</p>
                  </div>
                ))}
              </div>
            </section>
          )}

          {activeSection === 'monitoring' && (
            <section>
              <h2 className="text-2xl font-bold text-gray-800 mb-4">Monitoring & Analytics</h2>
              
              <div className="space-y-6">
                {monitoring.map((item) => (
                  <div key={item.category} className="border border-gray-200 rounded-lg overflow-hidden">
                    <div className="bg-yellow-50 px-4 py-2 border-b border-gray-200">
                      <h3 className="font-medium text-yellow-800">{item.category}</h3>
                    </div>
                    <div className="p-4">
                      <ul className="list-disc pl-5 space-y-1">
                        {item.items.map((practice, index) => (
                          <li key={index} className="text-gray-700">{practice}</li>
                        ))}
                      </ul>
                    </div>
                  </div>
                ))}
              </div>
            </section>
          )}
        </main>
      </div>

      <footer className="bg-gray-800 text-white py-6 mt-12">
        <div className="container mx-auto px-4 text-center">
          <p>TabletNotes MVP Implementation Plan</p>
          <p className="text-gray-400 text-sm mt-2">© 2025 TabletNotes</p>
        </div>
      </footer>
    </div>
  )
}

export default App
