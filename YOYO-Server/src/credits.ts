export const PRO_MONTHLY_CREDITS = 100;
export const DEFAULT_FREE_CREDITS = 0;

export interface UserCredits {
  credits: number;
  subscriptionStatus: number; // 0: free, 1: pro
}

export class CreditService {
  private env: Env;

  constructor(env: Env) {
    this.env = env;
  }

  /**
   * Gets the user's credits and handles the monthly auto-reset logic.
   */
  async getUserCredits(userId: number): Promise<UserCredits | null> {
    const user = await this.env.DB.prepare(
      "SELECT credits, subscription_status, last_credit_reset_date, subscription_end_date FROM users WHERE id = ?"
    )
      .bind(userId)
      .first<{
        credits: number;
        subscription_status: number;
        last_credit_reset_date: string;
        subscription_end_date: string | null;
      }>();

    if (!user) {
      return null;
    }

    let credits = user.credits ?? DEFAULT_FREE_CREDITS;
    let status = user.subscription_status ?? 0;

    // Double check expiration to prevent giving pro credits to expired users
    if (status === 1 && user.subscription_end_date) {
      const endDate = new Date(user.subscription_end_date);
      if (endDate.getTime() < Date.now()) {
        status = 0;
      }
    }

        // REMOVED: Automatic monthly reset logic based on date.
    
    return {
      credits,
      subscriptionStatus: status,
    };
  }

  /**
   * Deducts credits from the user.
   * @returns The remaining credits after deduction
   * @throws Error If the user does not have enough credits
   */
  async deductCredits(userId: number, amount: number = 1): Promise<number> {
    // Ensure monthly reset is processed first
    const user = await this.getUserCredits(userId);
    if (!user) {
      throw new Error("User not found");
    }

    // Atomic update to prevent race conditions
    const result = await this.env.DB.prepare(
      "UPDATE users SET credits = credits - ? WHERE id = ? AND credits >= ? RETURNING credits"
    )
      .bind(amount, userId, amount)
      .first<{ credits: number }>();

    if (!result) {
      throw new Error("Insufficient credits");
    }

    return result.credits;
  }
}
