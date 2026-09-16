"use client"

import { FadeUp } from "@/components/motion"

export function Philosophy() {
  return (
    <section className="bg-[#F7F8FA] text-[#1F1F23] py-24 md:py-32 px-6">
      <div className="max-w-xl mx-auto text-center">
        <FadeUp>
          <h3 className="text-2xl md:text-3xl font-medium tracking-tight mb-8 text-balance">
            Listening is not the end of the practice.
          </h3>
        </FadeUp>

        <div className="flex flex-col gap-8 text-base md:text-lg text-[#1F1F23]/80 font-normal leading-relaxed">
          <FadeUp delay={0.1}>
            <p>
              Listening opens the door. Writing is how you walk through it.
            </p>
          </FadeUp>
          <FadeUp delay={0.2}>
            <p>
              Tablet Notes isn&apos;t a recorder. It&apos;s a practice — for people who believe what they hear is worth carrying with them.
            </p>
          </FadeUp>
          <FadeUp delay={0.3}>
            <p>The AI is a guide. The writing is yours.</p>
          </FadeUp>
        </div>
      </div>
    </section>
  )
}
