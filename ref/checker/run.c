/* run.c — 用 plymouth 自己的脚本引擎离线驱动 hdd-boot.script
 * 用法: run <stub.script> <hdd-boot.script> <scenario>
 *   scenario 1: 动画未播完 + 无按键 + quit          -> 不允许退出
 *   scenario 2: 动画播完一轮                        -> 允许退出, 且停在最后一帧
 *   scenario 3: 未播完 + 按键(启动未完成)            -> 不允许; 启动完成后 -> 允许
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "script.h"
#include "script-parse.h"
#include "script-object.h"
#include "script-execute.h"

static script_state_t *state;

static void
run_file (const char *path)
{
        script_op_t *op = script_parse_file (path);
        if (op == NULL) { fprintf (stderr, "parse failed: %s\n", path); exit (1); }
        script_return_t ret = script_execute (state, op);
        script_obj_unref (ret.object);
}

static script_obj_t *
global_obj (const char *name)
{
        return script_obj_hash_get_element (state->global, name);
}

static double
global_num (const char *name)
{
        script_obj_t *o = global_obj (name);
        double n = script_obj_as_number (o);
        script_obj_unref (o);
        return n;
}

static double
member_num (const char *hash_name, const char *member)
{
        script_obj_t *h = global_obj (hash_name);
        script_obj_t *v = script_obj_hash_get_element (h, member);
        double n = script_obj_as_number (v);
        script_obj_unref (v);
        script_obj_unref (h);
        return n;
}

static void
call_func (script_obj_t *func, script_obj_t *a1, script_obj_t *a2)
{
        script_return_t ret;
        if (func == NULL) { printf ("  !! callback not registered\n"); return; }
        ret = script_execute_object (state, func, NULL, a1, a2, NULL);
        script_obj_unref (ret.object);
}

static void
call_refresh (void) { call_func (global_obj ("stub_refresh"), NULL, NULL); }

static void
call_key (const char *k)
{
        script_obj_t *s = script_obj_new_string (k);
        call_func (global_obj ("stub_key"), s, NULL);
        script_obj_unref (s);
}

static void
call_progress (double progress)
{
        script_obj_t *d = script_obj_new_number (10.0);
        script_obj_t *p = script_obj_new_number (progress);
        call_func (global_obj ("stub_progress"), d, p);
        script_obj_unref (d);
        script_obj_unref (p);
}

static void
call_message (const char *msg)
{
        script_obj_t *s = script_obj_new_string (msg);
        call_func (global_obj ("stub_message"), s, NULL);
        script_obj_unref (s);
}

static void
call_quit (void) { call_func (global_obj ("stub_quit"), NULL, NULL); }

static void
report (const char *label)
{
        printf ("  [%s] index=%g ticks_done=%g key=%g boot_complete=%g exit_allowed=%g log_lines=%g\n",
                label,
                member_num ("anim", "index"),
                member_num ("anim", "done"),
                member_num ("anim", "key_pressed"),
                member_num ("anim", "boot_complete"),
                member_num ("anim", "exit_allowed"),
                member_num ("log", "count"));
}

int
main (int argc, char **argv)
{
        int scenario = (argc > 3) ? atoi (argv[3]) : 1;
        int i;

        state = script_state_new (NULL);
        run_file (argv[1]);
        run_file (argv[2]);

        printf ("== scenario %d ==\n", scenario);
        printf ("  registered: refresh_rate=%g refresh_fn=%d key_fn=%d quit_fn=%d\n",
                global_num ("fps_stub"),
                global_obj ("stub_refresh") != NULL,
                global_obj ("stub_key") != NULL,
                global_obj ("stub_quit") != NULL);
        report ("init");

        if (scenario == 1)
        {
                for (i = 0; i < 50; i++) call_refresh ();
                report ("50 ticks (未播完)");
                call_quit ();
                report ("quit (无按键, 启动完成)");
                for (i = 0; i < 50; i++) call_refresh ();
                report ("quit 后再 50 ticks");
        }
        else if (scenario == 2)
        {
                for (i = 0; i < 400; i++) call_refresh ();
                report ("400 ticks (应播完一轮并停在最后一帧)");
                call_quit ();
                report ("quit");
        }
        else if (scenario == 3)
        {
                for (i = 0; i < 30; i++) call_refresh ();
                call_key ("a");
                report ("按键 (启动未完成)");
                call_progress (0.5);
                report ("progress=0.5");
                call_progress (1.0);
                report ("progress=1.0");
                call_quit ();
                report ("quit");
        }
        else if (scenario == 4)
        {
                /* 日志滚动 + 消息回调 */
                for (i = 1; i <= 12; i++)
                {
                        char buf[64];
                        snprintf (buf, sizeof (buf), "boot message line %d", i);
                        call_message (buf);
                }
                report ("12 条消息后 (日志应滚动到 8 行)");
                {
                        char *s = script_obj_as_string (global_obj ("stub_last_text"));
                        printf ("  last_text=%s\n", s ? s : "(null)");
                        free (s);
                }
        }

        return 0;
}
