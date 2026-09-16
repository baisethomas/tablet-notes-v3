import { z } from "zod"

// Email validation schema
export const emailSchema = z.object({
  email: z.string().email({ message: "Please enter a valid email address" }),
  consent: z.boolean().refine((val) => val === true, {
    message: "You must agree to receive emails",
  }),
})

export type EmailFormData = z.infer<typeof emailSchema>

// Function to validate email format
export function isValidEmail(email: string): boolean {
  try {
    z.string().email().parse(email)
    return true
  } catch {
    return false
  }
}

// In a real application, you would add functions to:
// 1. Store subscribers in a database
// 2. Check if an email already exists
// 3. Handle unsubscribe requests
// 4. Track email engagement

// Example function for storing subscribers (placeholder)
export async function storeSubscriber(email: string): Promise<boolean> {
  try {
    // In a real app, you would store this in a database
    console.log(`Storing subscriber: ${email}`)
    return true
  } catch (error) {
    console.error("Error storing subscriber:", error)
    return false
  }
}
