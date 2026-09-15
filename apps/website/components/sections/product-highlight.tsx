"use client"

import Image from "next/image"
import { FadeUp } from "@/components/motion"
import { motion } from "framer-motion"

export function ProductHighlight() {
  return (
    <section className="bg-[#FFFFFF] py-24 md:py-32 overflow-hidden relative">
      <div className="flex items-center">
        {/* Text Content -- pushed left to make room for the phone */}
        <div className="max-w-4xl mx-auto text-center px-6 md:text-left md:pl-12 lg:pl-24 md:mx-0 md:max-w-lg lg:max-w-2xl">
          <FadeUp>
            <h3 className="text-2xl md:text-3xl font-medium tracking-tight text-[#1F1F23] mb-3">
              What your notes deserve.
            </h3>
          </FadeUp>
          <FadeUp delay={0.15}>
            <p className="text-[#1F1F23]/60 text-base font-normal">
              A space that takes your Sunday morning as seriously as you do.
            </p>
          </FadeUp>
        </div>

        {/* iPhone -- slides in from the right */}
        <motion.div
          initial={{ opacity: 0, x: 80 }}
          whileInView={{ opacity: 1, x: 0 }}
          viewport={{ once: true, margin: "-80px" }}
          transition={{ duration: 0.8, ease: [0.25, 0.1, 0.25, 1], delay: 0.2 }}
          className="hidden md:block absolute right-0 top-1/2 -translate-y-1/2 md:translate-x-[42%] lg:translate-x-[30%] w-[270px] lg:w-[340px] xl:w-[400px]"
        >
          <Image
            src="/images/hero-phone-dark.png"
            alt="Tablet Notes app dark mode showing sermon summary"
            width={400}
            height={820}
            className="w-full h-auto drop-shadow-2xl"
          />
        </motion.div>
      </div>
    </section>
  )
}
