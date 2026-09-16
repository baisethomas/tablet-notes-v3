"use client"

import { FadeUp, StaggerChildren, StaggerItem } from "@/components/motion"

const columns = [
  {
    title: "Capture",
    description:
      "Your pen moves while the message unfolds. A clean, distraction-free space designed to get out of the way.",
  },
  {
    title: "Reflect",
    description:
      "After the message, the work begins. Review what landed, connect what matters, let the ideas settle into something you can act on.",
  },
  {
    title: "Retain",
    description:
      "A note you wrote is a note you kept. Tablet Notes is built around the belief that active inscription is how wisdom takes hold.",
  },
]

export function Experience() {
  return (
    <section className="bg-[#F7F8FA] text-[#1F1F23] pb-24 md:pb-32 px-6 border-t border-[#1F1F23]/5">
      <div className="max-w-6xl mx-auto">
        <FadeUp>
          <h3 className="text-2xl md:text-3xl font-medium tracking-tight text-center md:text-left pt-24 mb-16">
            Designed for focused reflection.
          </h3>
        </FadeUp>

        <StaggerChildren className="grid grid-cols-1 md:grid-cols-3 gap-12 md:gap-8">
          {columns.map((col) => (
            <StaggerItem key={col.title}>
              <div className="flex flex-col gap-3">
                <h4 className="text-lg font-medium tracking-tight">{col.title}</h4>
                <p className="text-sm text-[#1F1F23]/70 leading-relaxed max-w-xs">
                  {col.description}
                </p>
              </div>
            </StaggerItem>
          ))}
        </StaggerChildren>
      </div>
    </section>
  )
}
