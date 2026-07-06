/* Reproduce the reported bug: a player with NO guns is attacked by cops.
 * The UI shows Stand and Run; clicking them "does nothing". Drive the
 * bridge exactly as the buttons do and observe whether the fight
 * progresses. */
#include <stdio.h>
#include <string.h>
#include "dpbridge.h"

static int fights_seen = 0, stand_progress = 0, run_progress = 0;
static int msgs_since_action = 0;
static int q_pending = 0;
static char q_allowed[16], q_prompt[512];
static int gameover = 0;

static void on_event(DPEventKind kind, const char *s1, const char *s2, void *u)
{
  (void)u;
  switch (kind) {
  case DP_EV_FIGHT:
    msgs_since_action++;
    printf("  [fight] '%s' fp=%c fire=%d runhere=%d guns=%d fighting=%d\n",
           s1 ? s1 : "", dp_fight_point() ? dp_fight_point() : '0',
           dp_fight_can_fire(), dp_fight_can_run_here(),
           dp_total_guns(), dp_is_fighting());
    break;
  case DP_EV_QUESTION:
    snprintf(q_allowed, sizeof(q_allowed), "%s", s1 ? s1 : "");
    snprintf(q_prompt, sizeof(q_prompt), "%s", s2 ? s2 : "");
    q_pending = 1;
    break;
  case DP_EV_LOANSHARK:
  case DP_EV_BANK:
  case DP_EV_GUNSHOP:
    dp_done();
    break;
  case DP_EV_SUBWAY:
    printf("  [subway] arrived %s\n", s1 ? s1 : "");
    break;
  case DP_EV_GAMEOVER:
    gameover = 1;
    break;
  default:
    break;
  }
}

int main(void)
{
  int game, step;

  dp_init(NULL, "/tmp/dopewars_gunlesstest.sco");
  dp_set_callback(on_event, NULL);

  for (game = 0; game < 40 && fights_seen < 4; game++) {
    gameover = 0;
    q_pending = 0;
    dp_new_game("Gunless");

    for (step = 0; step < 3000 && !gameover; step++) {
      if (q_pending) {
        q_pending = 0;
        dp_answer("N");                     /* never visit shops/banks */
      } else if (dp_fight_point() != 0 || dp_is_fighting()) {
        char fp = dp_fight_point();
        if (dp_is_dead()) break;
        if (fp == 'D') {
          printf("  -> fight over; acknowledging\n");
          dp_fight_finish();
          continue;
        }
        fights_seen++;
        if (fights_seen % 2 == 1) {
          /* Odd fights: press "Stand" like the UI button does. */
          printf("  -> clicking STAND (fire=%d runhere=%d)\n",
                 dp_fight_can_fire(), dp_fight_can_run_here());
          msgs_since_action = 0;
          dp_fight_stand();
          printf("  -> stand produced %d fight message(s)\n",
                 msgs_since_action);
          if (msgs_since_action > 0) stand_progress = 1;
          else {
            printf("  !! STALL after Stand\n");
            break;
          }
        } else {
          /* Even fights: press "Run". */
          printf("  -> clicking RUN (fire=%d runhere=%d)\n",
                 dp_fight_can_fire(), dp_fight_can_run_here());
          msgs_since_action = 0;
          if (dp_fight_can_run_here()) {
            dp_fight_run();
          } else {
            dp_jet((dp_location() + 1) % dp_num_locations());
          }
          printf("  -> run produced %d fight message(s), fighting=%d\n",
                 msgs_since_action, dp_is_fighting());
          if (msgs_since_action > 0 || !dp_is_fighting()) run_progress = 1;
          else {
            printf("  !! STALL after Run\n");
            break;
          }
        }
      } else if (dp_is_dead()) {
        break;
      } else {
        /* Buy the cheapest drug (stay "carrying") and jet 0<->1. */
        int i, best = -1; long long bestp = 0;
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
        if (!q_pending && !dp_is_fighting())
          dp_jet(dp_location() == 0 ? 1 : 0);
      }
    }
  }

  printf("\nfights seen: %d, stand progressed: %s, run progressed: %s\n",
         fights_seen, stand_progress ? "YES" : "NO",
         run_progress ? "YES" : "NO");
  return (stand_progress && run_progress) ? 0 : 1;
}
