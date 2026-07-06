/* Regression test: buying a gun at the store with a mostly-full coat.
 *
 * Player.CoatSize in the engine counts REMAINING space. The old bridge
 * treated it as capacity, computing free = CoatSize - used, which goes
 * negative once the coat is over half full — blocking all purchases in
 * the UI while selling still worked. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "dpbridge.h"

static int q_pending = 0, in_gunshop = 0, gameover = 0;
static char q_prompt[512];

static void on_event(DPEventKind kind, const char *s1, const char *s2, void *u)
{
  (void)u;
  switch (kind) {
  case DP_EV_QUESTION:
    snprintf(q_prompt, sizeof(q_prompt), "%s", s2 ? s2 : "");
    q_pending = 1;
    break;
  case DP_EV_GUNSHOP: in_gunshop = 1; break;
  case DP_EV_LOANSHARK:
  case DP_EV_BANK: dp_done(); break;
  case DP_EV_GAMEOVER: gameover = 1; break;
  default: break;
  }
}

static int check_invariant(const char *when)
{
  int free_ = dp_space_free(), used = dp_coat_used(), size = dp_coat_size();
  if (free_ + used != size) {
    printf("FAIL invariant at %s: free=%d used=%d size=%d\n",
           when, free_, used, size);
    return 0;
  }
  printf("  [%s] free=%d used=%d size=%d OK\n", when, free_, used, size);
  return 1;
}

/* Phases: earn cash trading, then fill >half the coat with cheap drugs
 * (so the old buggy formula would refuse), then buy the gun. */
enum { EARN, FILL, BUYGUN };
static int phase = EARN;

static int cheapest_drug(long long *price_out)
{
  int i, best = -1; long long bestp = 0;
  for (i = 0; i < dp_num_drugs(); i++) {
    long long p = dp_drug_price(i);
    if (p > 0 && (best < 0 || p < bestp)) { best = i; bestp = p; }
  }
  if (price_out) *price_out = bestp;
  return best;
}

int main(void)
{
  int i, step, game;
  int bought_with_full_coat = 0, sold_ok = 0, invariants_ok = 1;
  const long long gun_budget = 3500;

  dp_init(NULL, "/tmp/dopewars_gunbuytest.sco");
  dp_set_callback(on_event, NULL);

  for (game = 0; game < 25 && !bought_with_full_coat; game++) {
    gameover = 0; q_pending = 0; in_gunshop = 0; phase = EARN;
    dp_new_game("Buyer");
    if (game == 0) invariants_ok &= check_invariant("game start");

    for (step = 0; step < 3000 && !gameover && !bought_with_full_coat; step++) {
      if (q_pending) {
        q_pending = 0;
        if ((strstr(q_prompt, "Guns") || strstr(q_prompt, "guns"))
            && phase == BUYGUN) {
          dp_answer("Y");
        } else {
          dp_answer("N");
        }
      } else if (in_gunshop) {
        in_gunshop = 0;
        {
          int before = dp_total_guns();
          long long cash_before = dp_cash();
          int free_before = dp_space_free();
          int used = dp_coat_used();
          int old_formula_free = free_before - used;   /* the buggy view */
          printf("In gun shop: cash=%lld used=%d free=%d (old formula said %d) guns=%d\n",
                 cash_before, used, free_before, old_formula_free, before);
          printf("  -> old formula would have %s this buy\n",
                 old_formula_free < dp_gun_space(0) ? "BLOCKED" : "allowed");
          if (cash_before >= dp_gun_price(0)
              && free_before >= dp_gun_space(0)) {
            dp_buy_gun(0, 1);
            if (dp_total_guns() == before + 1
                && dp_space_free() == free_before - dp_gun_space(0)
                && dp_cash() == cash_before - dp_gun_price(0)) {
              printf("  BUY OK: guns=%d free=%d cash=%lld\n",
                     dp_total_guns(), dp_space_free(), dp_cash());
              bought_with_full_coat = (dp_coat_used() > dp_space_free());
              invariants_ok &= check_invariant("after gun buy");
              dp_buy_gun(0, -1);
              if (dp_total_guns() == before) {
                sold_ok = 1;
                printf("  SELL OK: guns=%d free=%d\n",
                       dp_total_guns(), dp_space_free());
              }
              invariants_ok &= check_invariant("after gun sell");
            } else {
              printf("  BUY FAILED unexpectedly\n");
            }
          }
        }
        dp_done();
      } else if (dp_fight_point() != 0 || dp_is_fighting()) {
        if (dp_is_dead()) break;
        if (dp_fight_point() == 'D') dp_fight_finish();
        else if (dp_fight_can_run_here()) dp_fight_run();
        else dp_jet((dp_location() + 1) % dp_num_locations());
      } else if (dp_is_dead()) {
        break;
      } else if (phase == EARN) {
        /* Sell everything, buy cheapest, bounce; hope for price spikes. */
        for (i = 0; i < dp_num_drugs(); i++) {
          if (dp_drug_carried(i) > 0 && dp_drug_price(i) > 0)
            dp_buy_drug(i, -dp_drug_carried(i));
        }
        if (dp_cash() >= gun_budget + 1500) {
          phase = FILL;
          continue;
        }
        {
          long long p; int best = cheapest_drug(&p);
          if (best >= 0) {
            int n = (int)((dp_cash() - 100) / p);
            if (n > dp_space_free()) n = dp_space_free();
            if (n > 0) dp_buy_drug(best, n);
          }
        }
        if (!q_pending && !dp_is_fighting())
          dp_jet(dp_location() == 0 ? 1 : 0);
      } else if (phase == FILL) {
        /* Keep the gun budget in cash; pack the coat past half full. */
        long long p; int best = cheapest_drug(&p);
        if (best >= 0 && dp_coat_used() < 55) {
          long long spare = dp_cash() - gun_budget;
          int n = spare > 0 ? (int)(spare / p) : 0;
          if (n > 55 - dp_coat_used()) n = 55 - dp_coat_used();
          if (n > dp_space_free()) n = dp_space_free();
          if (n > 0) dp_buy_drug(best, n);
        }
        if (dp_coat_used() >= 52 && dp_cash() >= gun_budget) {
          printf("Coat packed: used=%d free=%d cash=%lld -> heading to gun shop\n",
                 dp_coat_used(), dp_space_free(), dp_cash());
          phase = BUYGUN;
        } else if (dp_cash() < gun_budget) {
          phase = EARN;                     /* prices moved; earn more */
        }
        if (!q_pending && !dp_is_fighting() && phase != BUYGUN)
          dp_jet(dp_location() == 0 ? 1 : 0);
        if (phase == BUYGUN && !q_pending && !dp_is_fighting())
          dp_jet(dp_location() == 1 ? 0 : 1);
      } else {                              /* BUYGUN: bounce, answer Y */
        if (!q_pending && !dp_is_fighting())
          dp_jet(dp_location() == 0 ? 1 : 0);
      }
    }
  }

  printf("\nbought with >half-full coat: %s, sold: %s, invariants: %s (games=%d)\n",
         bought_with_full_coat ? "YES" : "NO",
         sold_ok ? "YES" : "NO",
         invariants_ok ? "OK" : "BROKEN", game);
  if (bought_with_full_coat && sold_ok && invariants_ok) {
    printf("GUNBUYTEST OK\n");
    return 0;
  }
  printf("GUNBUYTEST FAILED\n");
  return 1;
}
