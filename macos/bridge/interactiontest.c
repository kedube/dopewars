/* Comprehensive headless interaction test for the macOS bridge.
 *
 * Drives the engine the same way the AppKit UI does: the event callback
 * only records what arrived; all actions are taken from the main loop
 * (mirroring the async nature of sheets/alerts). Plays as many games as
 * needed to exercise every interaction:
 *   - buying, selling, and dropping drugs
 *   - jetting between locations
 *   - answering questions
 *   - the gun shop (buy a gun)
 *   - the loan shark (pay debt)
 *   - the bank (deposit + withdraw)
 *   - fights: shoot, run-in-place, flee-by-jet, and the fight-over ack
 *   - high scores / game over / starting a new game
 */
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include "dpbridge.h"

/* --- recorded state (set by callback, consumed by main loop) --------- */
static char q_allowed[16];
static char q_prompt[512];
static int q_pending = 0;
static int in_loanshark = 0, in_bank = 0, in_gunshop = 0;
static int gameover = 0;

/* --- coverage flags --------------------------------------------------- */
static int saw_fight = 0, fight_shots = 0, fight_ran = 0, fight_fled_jet = 0;
static int fight_completed = 0, fight_died = 0, fight_failflee = 0;
static int did_gunshop = 0, did_bank = 0, did_loanshark = 0;
static int did_drop = 0, did_sell = 0;
static int saw_hiscores = 0, saw_gameover = 0;
static int games_played = 0;

static void on_event(DPEventKind kind, const char *s1, const char *s2, void *u)
{
  (void)u;
  switch (kind) {
  case DP_EV_QUESTION:
    snprintf(q_allowed, sizeof(q_allowed), "%s", s1 ? s1 : "");
    snprintf(q_prompt, sizeof(q_prompt), "%s", s2 ? s2 : "");
    q_pending = 1;
    break;
  case DP_EV_LOANSHARK: in_loanshark = 1; break;
  case DP_EV_BANK:      in_bank = 1; break;
  case DP_EV_GUNSHOP:   in_gunshop = 1; break;
  case DP_EV_FIGHT:
    saw_fight = 1;
    if (s1 && s1[0])
      printf("    [fight] %s (fp=%c fire=%d runhere=%d)\n", s1,
             dp_fight_point() ? dp_fight_point() : '0',
             dp_fight_can_fire(), dp_fight_can_run_here());
    if (dp_fight_point() == 'F')
      fight_failflee = 1;
    break;
  case DP_EV_HISCORE_START: saw_hiscores = 1; break;
  case DP_EV_GAMEOVER: saw_gameover = 1; gameover = 1; break;
  case DP_EV_PRINT:
  case DP_EV_MESSAGE:
  case DP_EV_SUBWAY:
  case DP_EV_UPDATE:
  case DP_EV_HISCORE_LINE:
  case DP_EV_HISCORE_END:
  default:
    break;
  }
}

static void answer_question(void)
{
  const char *ans = "N";
  q_pending = 0;
  if (strstr(q_prompt, "Guns") || strstr(q_prompt, "guns")) {
    ans = (dp_total_guns() == 0 && dp_cash() > 500) ? "Y" : "N";
  } else if (strstr(q_prompt, "Loan Shark")) {
    ans = (!did_loanshark && dp_debt() > 0 && dp_cash() > 500) ? "Y" : "N";
  } else if (strstr(q_prompt, "Bank")) {
    ans = (!did_bank && dp_cash() > 600) ? "Y" : "N";
  } else if (strchr(q_allowed, 'Y') == NULL && q_allowed[0]) {
    /* Question without a "No" option (e.g. old-style run-or-fight):
     * take the first allowed letter. */
    char one[2] = { q_allowed[0], 0 };
    dp_answer(one);
    return;
  }
  dp_answer(ans);
}

static void handle_fight(void)
{
  char fp = dp_fight_point();
  if (fp == 'D') {                       /* fight over: acknowledge */
    dp_fight_finish();
    fight_completed = 1;
    printf("    [fight] completed + acknowledged\n");
  } else if (dp_fight_can_fire() && dp_total_guns() > 0) {
    fight_shots++;
    dp_fight_shoot();
  } else if (dp_fight_can_run_here()) {
    fight_ran = 1;
    dp_fight_run();
  } else if (dp_fight_can_fire()) {      /* no guns: stand */
    dp_fight_stand();
  } else {
    /* Flee by jetting elsewhere */
    fight_fled_jet = 1;
    dp_jet((dp_location() + 1) % dp_num_locations());
  }
}

static void street_turn(int t)
{
  int i;
  /* Sell carried drugs with a market here; drop worthless ones. */
  for (i = 0; i < dp_num_drugs(); i++) {
    int carried = dp_drug_carried(i);
    if (carried <= 0) continue;
    if (dp_drug_price(i) > 0) {
      dp_buy_drug(i, -carried);
      did_sell = 1;
    } else if (!did_drop) {
      dp_buy_drug(i, -1);
      did_drop = 1;
      printf("    [drop] dropped 1 worthless unit\n");
    }
  }
  if (q_pending || in_gunshop || in_bank || in_loanshark || gameover)
    return;                               /* events interrupted trading */
  /* Buy the cheapest available drug we can afford (keeps us "carrying"). */
  {
    int best = -1; long long bestp = 0;
    for (i = 0; i < dp_num_drugs(); i++) {
      long long p = dp_drug_price(i);
      if (p > 0 && p <= dp_cash() && (best < 0 || p < bestp)) {
        best = i; bestp = p;
      }
    }
    if (best >= 0) {
      int n = (int)(dp_cash() / bestp);
      int space = dp_coat_size() - dp_coat_used();
      if (n > space) n = space;
      if (n > 8) n = 8;
      if (n > 0) dp_buy_drug(best, n);
    }
  }
  if (q_pending || in_gunshop || in_bank || in_loanshark || gameover)
    return;
  /* Jet between Bronx (0) and Ghetto (1): high police presence and all
   * the special buildings. */
  dp_jet(dp_location() == 0 ? 1 : 0);
  (void)t;
}

int main(void)
{
  int safety;

  dp_init(NULL, "/tmp/dopewars_interactiontest.sco");
  dp_set_callback(on_event, NULL);

  while (games_played < 60 && !(fight_completed && did_gunshop &&
                                did_bank && did_loanshark && did_drop)) {
    gameover = 0;
    q_pending = in_loanshark = in_bank = in_gunshop = 0;
    dp_new_game("Tester");
    games_played++;

    for (safety = 0; safety < 5000 && !gameover; safety++) {
      if (q_pending) {
        answer_question();
      } else if (in_gunshop) {
        in_gunshop = 0;
        if (dp_total_guns() == 0 && dp_gun_price(0) <= dp_cash()
            && dp_gun_space(0) <= dp_coat_size() - dp_coat_used()) {
          dp_buy_gun(0, 1);
          if (dp_total_guns() > 0) {
            did_gunshop = 1;
            printf("    [gunshop] bought a %s\n", dp_gun_name(0));
          }
        }
        dp_done();
      } else if (in_loanshark) {
        in_loanshark = 0;
        {
          long long pay = dp_debt() < dp_cash() ? dp_debt() : dp_cash();
          long long before = dp_debt();
          if (pay > 0) dp_pay_loan(pay);
          if (dp_debt() < before) {
            did_loanshark = 1;
            printf("    [loanshark] paid %lld, debt now %lld\n",
                   pay, dp_debt());
          }
        }
        dp_done();
      } else if (in_bank) {
        in_bank = 0;
        {
          long long before = dp_bank();
          dp_bank_deposit(500);
          dp_bank_deposit(-200);
          if (dp_bank() == before + 300) {
            did_bank = 1;
            printf("    [bank] deposit 500 / withdraw 200 OK (bank=%lld)\n",
                   dp_bank());
          }
        }
        dp_done();
      } else if (dp_fight_point() != 0 || dp_is_fighting()) {
        if (dp_is_dead()) { fight_died = 1; break; }
        handle_fight();
      } else if (dp_is_dead()) {
        break;
      } else {
        street_turn(safety);
      }
    }
    if (dp_is_dead() && saw_fight) fight_died = 1;
  }

  printf("\n=== COVERAGE after %d game(s) ===\n", games_played);
  printf("fight seen:            %s\n", saw_fight ? "YES" : "no");
  printf("fight shots fired:     %d\n", fight_shots);
  printf("fight ran in place:    %s\n", fight_ran ? "YES" : "no");
  printf("fight fled by jet:     %s\n", fight_fled_jet ? "YES" : "no");
  printf("fight failed flee:     %s\n", fight_failflee ? "YES" : "no");
  printf("fight completed+ack:   %s\n", fight_completed ? "YES" : "no");
  printf("died in fight:         %s\n", fight_died ? "YES" : "no");
  printf("gun shop purchase:     %s\n", did_gunshop ? "YES" : "no");
  printf("loan shark payment:    %s\n", did_loanshark ? "YES" : "no");
  printf("bank dep+withdraw:     %s\n", did_bank ? "YES" : "no");
  printf("sold drugs:            %s\n", did_sell ? "YES" : "no");
  printf("dropped worthless:     %s\n", did_drop ? "YES" : "no");
  printf("hiscores received:     %s\n", saw_hiscores ? "YES" : "no");
  printf("game over event:       %s\n", saw_gameover ? "YES" : "no");

  if (saw_fight && (fight_completed || fight_died) && did_gunshop &&
      did_bank && did_loanshark && did_sell && saw_hiscores && saw_gameover) {
    printf("\nINTERACTIONTEST OK\n");
    return 0;
  }
  printf("\nINTERACTIONTEST INCOMPLETE\n");
  return 1;
}
