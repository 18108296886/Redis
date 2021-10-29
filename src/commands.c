/* Automatically generated by generate-command-code.py, do not edit. */

#include "server.h"

/* Our command table.
*
* (See comment above sturct redisCommand)
*
* Command flags are expressed using space separated strings, that are turned
* into actual flags by the populateCommandTable() function.
*
* This is the meaning of the flags:
*
* write:       Write command (may modify the key space).
*
* read-only:   Commands just reading from keys without changing the content.
*              Note that commands that don't read from the keyspace such as
*              TIME, SELECT, INFO, administrative commands, and connection
*              or transaction related commands (multi, exec, discard, ...)
*              are not flagged as read-only commands, since they affect the
*              server or the connection in other ways.
*
* use-memory:  May increase memory usage once called. Don't allow if out
*              of memory.
*
* admin:       Administrative command, like SAVE or SHUTDOWN.
*
* pub-sub:     Pub/Sub related command.
*
* no-script:   Command not allowed in scripts.
*
* random:      Random command. Command is not deterministic, that is, the same
*              command with the same arguments, with the same key space, may
*              have different results. For instance SPOP and RANDOMKEY are
*              two random commands.
*
* to-sort:     Sort command output array if called from script, so that the
*              output is deterministic. When this flag is used (not always
*              possible), then the "random" flag is not needed.
*
* ok-loading:  Allow the command while loading the database.
*
* ok-stale:    Allow the command while a slave has stale data but is not
*              allowed to serve this data. Normally no command is accepted
*              in this condition but just a few.
*
* no-monitor:  Do not automatically propagate the command on MONITOR.
*
* no-slowlog:  Do not automatically propagate the command to the slowlog.
*
* cluster-asking: Perform an implicit ASKING for this command, so the
*              command will be accepted in cluster mode if the slot is marked
*              as 'importing'.
*
* fast:        Fast command: O(1) or O(log(N)) command that should never
*              delay its execution as long as the kernel scheduler is giving
*              us time. Note that commands that may trigger a DEL as a side
*              effect (like SET) are not fast commands.
* 
* may-replicate: Command may produce replication traffic, but should be 
*                allowed under circumstances where write commands are disallowed. 
*                Examples include PUBLISH, which replicates pubsub messages,and 
*                EVAL, which may execute write commands, which are replicated, 
*                or may just execute read commands. A command can not be marked 
*                both "write" and "may-replicate"
*
* sentinel: This command is present in sentinel mode too.
*
* sentinel-only: This command is present only when in sentinel mode.
*
* The following additional flags are only used in order to put commands
* in a specific ACL category. Commands can have multiple ACL categories.
* See redis.conf for the exact meaning of each.
*
* @keyspace, @read, @write, @set, @sortedset, @list, @hash, @string, @bitmap,
* @hyperloglog, @stream, @admin, @fast, @slow, @pubsub, @blocking, @dangerous,
* @connection, @transaction, @scripting, @geo.
*
* Note that:
*
* 1) The read-only flag implies the @read ACL category.
* 2) The write flag implies the @write ACL category.
* 3) The fast flag implies the @fast ACL category.
* 4) The admin flag implies the @admin and @dangerous ACL category.
* 5) The pub-sub flag implies the @pubsub ACL category.
* 6) The lack of fast flag implies the @slow ACL category.
* 7) The non obvious "keyspace" category includes the commands
*    that interact with keys without having anything to do with
*    specific data structures, such as: DEL, RENAME, MOVE, SELECT,
*    TYPE, EXPIRE*, PEXPIRE*, TTL, PTTL, ...
*/

/********** CONFIG SET ********************/

/* CONFIG SET return info */
commandReturnInfo CONFIG_SET_ReturnInfo[] = {
{"Command succeeded","+OK",RETURN_TYPE_RESP2_3_SAME,.type.global=RESP2_SIMPLE_STRING},
{0}
};

/* CONFIG SET history */
#define CONFIG_SET_History NULL

/* CONFIG SET parameter argument */
#define CONFIG_SET_parameter_Arg {"parameter",ARG_TYPE_STRING,NULL,NULL,NULL,0,0,.value.string="parameter"}

/* CONFIG SET value argument */
#define CONFIG_SET_value_Arg {"value",ARG_TYPE_STRING,NULL,NULL,NULL,0,0,.value.string="value"}

/* CONFIG SET argument table */
struct redisCommandArg CONFIG_SET_Args[] = {
CONFIG_SET_parameter_Arg,
CONFIG_SET_value_Arg,
{0}
};

/* CONFIG SET command */
#define CONFIG_SET_Command {"SET","Set a configuration parameter to the given value",NULL,"2.0.0",COMMAND_GROUP_GENERIC,CONFIG_SET_ReturnInfo,CONFIG_SET_History,configSetCommand,4,"admin no-script",.args=CONFIG_SET_Args}

/* CONFIG command table */
struct redisCommand CONFIG_Subcommands[] = {
CONFIG_SET_Command,
{0}
};

/********** CONFIG ********************/

/* CONFIG return info */
#define CONFIG_ReturnInfo NULL

/* CONFIG history */
#define CONFIG_History NULL

/* CONFIG command */
#define CONFIG_Command {"CONFIG",NULL,NULL,NULL,COMMAND_GROUP_GENERIC,CONFIG_ReturnInfo,CONFIG_History,NULL,-2,"",.subcommands=CONFIG_Subcommands}

/********** MIGRATE ********************/

/* MIGRATE return info */
commandReturnInfo MIGRATE_ReturnInfo[] = {
{"Command succeeded","+OK",RETURN_TYPE_RESP2_3_SAME,.type.global=RESP2_SIMPLE_STRING},
{"Key(s) was not in found in source","+NOKEY",RETURN_TYPE_RESP2_3_SAME,.type.global=RESP2_SIMPLE_STRING},
{0}
};

/* MIGRATE history */
commandHistory MIGRATE_History[] = {
{"3.0.0","Added the `COPY` and `REPLACE` options."},
{"3.0.6","Added the `KEYS` option."},
{"4.0.7","Added the `AUTH` option."},
{"6.0.0","Added the `AUTH2` option."},
{0}
};

/* MIGRATE host argument */
#define MIGRATE_host_Arg {"host",ARG_TYPE_STRING,NULL,NULL,NULL,0,0,.value.string="host"}

/* MIGRATE port argument */
#define MIGRATE_port_Arg {"port",ARG_TYPE_STRING,NULL,NULL,NULL,0,0,.value.string="port"}

/* MIGRATE keyornone key argument */
#define MIGRATE_keyornone_key_Arg {"key",ARG_TYPE_KEY,NULL,NULL,NULL,0,0,.value.string="key"}

/* MIGRATE keyornone nokey argument */
#define MIGRATE_keyornone_nokey_Arg {"nokey",ARG_TYPE_NULL,"""",NULL,NULL,0,0}

/* MIGRATE keyornone argument table */
struct redisCommandArg MIGRATE_keyornone_Subargs[] = {
MIGRATE_keyornone_key_Arg,
MIGRATE_keyornone_nokey_Arg,
{0}
};

/* MIGRATE keyornone argument */
#define MIGRATE_keyornone_Arg {"keyornone",ARG_TYPE_ONEOF,NULL,NULL,NULL,0,0,.value.subargs=MIGRATE_keyornone_Subargs}

/* MIGRATE destination_db argument */
#define MIGRATE_destination_db_Arg {"destination-db",ARG_TYPE_INTEGER,NULL,NULL,NULL,0,0,.value.string="destination-db"}

/* MIGRATE timeout argument */
#define MIGRATE_timeout_Arg {"timeout",ARG_TYPE_INTEGER,NULL,NULL,NULL,0,0,.value.string="timeout"}

/* MIGRATE copy argument */
#define MIGRATE_copy_Arg {"copy",ARG_TYPE_NULL,"COPY",NULL,NULL,1,0}

/* MIGRATE replace argument */
#define MIGRATE_replace_Arg {"replace",ARG_TYPE_NULL,"REPLACE",NULL,NULL,1,0}

/* MIGRATE auth argument */
#define MIGRATE_auth_Arg {"auth",ARG_TYPE_STRING,"AUTH",NULL,NULL,1,0,.value.string="password"}

/* MIGRATE auth2 username argument */
#define MIGRATE_auth2_username_Arg {"username",ARG_TYPE_STRING,NULL,NULL,NULL,0,0,.value.string="username"}

/* MIGRATE auth2 password argument */
#define MIGRATE_auth2_password_Arg {"password",ARG_TYPE_STRING,NULL,NULL,NULL,0,0,.value.string="password"}

/* MIGRATE auth2 argument table */
struct redisCommandArg MIGRATE_auth2_Subargs[] = {
MIGRATE_auth2_username_Arg,
MIGRATE_auth2_password_Arg,
{0}
};

/* MIGRATE auth2 argument */
#define MIGRATE_auth2_Arg {"auth2",ARG_TYPE_BLOCK,"AUTH2",NULL,NULL,1,0,.value.subargs=MIGRATE_auth2_Subargs}

/* MIGRATE keys argument */
#define MIGRATE_keys_Arg {"keys",ARG_TYPE_KEY,"KEYS",NULL,NULL,1,1,.value.string="key"}

/* MIGRATE argument table */
struct redisCommandArg MIGRATE_Args[] = {
MIGRATE_host_Arg,
MIGRATE_port_Arg,
MIGRATE_keyornone_Arg,
MIGRATE_destination_db_Arg,
MIGRATE_timeout_Arg,
MIGRATE_copy_Arg,
MIGRATE_replace_Arg,
MIGRATE_auth_Arg,
MIGRATE_auth2_Arg,
MIGRATE_keys_Arg,
{0}
};

/* MIGRATE command */
#define MIGRATE_Command {"MIGRATE","Atomically transfer a key from a Redis instance to another one.","This command actually executes a DUMP+DEL in the source instance, and a RESTORE in the target instance. See the pages of these commands for time complexity. Also an O(N) data transfer between the two instances is performed.","2.6.0",COMMAND_GROUP_GENERIC,MIGRATE_ReturnInfo,MIGRATE_History,migrateCommand,-6,"write random @keyspace @dangerous @write @slow",{{"write",KSPEC_BS_INDEX,.bs.index={3},KSPEC_FK_RANGE,.fk.range={0,1,0}},{"write incomplete",KSPEC_BS_KEYWORD,.bs.keyword={"KEYS",-2},KSPEC_FK_RANGE,.fk.range={-1,1,0}}},migrateGetKeys,.args=MIGRATE_Args}

/********** COMMAND COUNT ********************/

/* COMMAND COUNT return info */
commandReturnInfo COMMAND_COUNT_ReturnInfo[] = {
{"Number of commands",NULL,RETURN_TYPE_RESP2_3_SAME,.type.global=RESP2_INTEGER},
{0}
};

/* COMMAND COUNT history */
#define COMMAND_COUNT_History NULL

/* COMMAND COUNT command */
#define COMMAND_COUNT_Command {"COUNT","Get total number of Redis commands","O(1)","2.8.13",COMMAND_GROUP_SERVER,COMMAND_COUNT_ReturnInfo,COMMAND_COUNT_History,commandCountCommand,2,"ok-loading ok-stale @connection"}

/********** COMMAND GETKEYS ********************/

/* COMMAND GETKEYS return info */
commandReturnInfo COMMAND_GETKEYS_ReturnInfo[] = {
{"The list of keys from your command",NULL,RETURN_TYPE_RESP2_3_SAME,.type.global=RESP2_ARRAY},
{0}
};

/* COMMAND GETKEYS history */
#define COMMAND_GETKEYS_History NULL

/* COMMAND GETKEYS command */
#define COMMAND_GETKEYS_Command {"GETKEYS","Extract keys given a full Redis command","O(N) where N is the number of arguments to the command","2.8.13",COMMAND_GROUP_SERVER,COMMAND_GETKEYS_ReturnInfo,COMMAND_GETKEYS_History,commandGetKeysCommand,-4,"ok-loading ok-stale @connection"}

/* COMMAND command table */
struct redisCommand COMMAND_Subcommands[] = {
COMMAND_COUNT_Command,
COMMAND_GETKEYS_Command,
{0}
};

/********** COMMAND ********************/

/* COMMAND return info */
commandReturnInfo COMMAND_ReturnInfo[] = {
{"Nested list of command details",NULL,RETURN_TYPE_RESP2_3_SAME,.type.global=RESP2_ARRAY},
{0}
};

/* COMMAND history */
#define COMMAND_History NULL

/* COMMAND command */
#define COMMAND_Command {"COMMAND","Get array of Redis command details","O(N) where N is the total number of Redis commands","2.8.13",COMMAND_GROUP_SERVER,COMMAND_ReturnInfo,COMMAND_History,commandCommand,-1,"ok-loading ok-stale @connection",.subcommands=COMMAND_Subcommands}

/********** ZUNIONSTORE ********************/

/* ZUNIONSTORE return info */
commandReturnInfo ZUNIONSTORE_ReturnInfo[] = {
{"Cardinality of the result",NULL,RETURN_TYPE_RESP2_3_SAME,.type.global=RESP2_INTEGER},
{0}
};

/* ZUNIONSTORE history */
#define ZUNIONSTORE_History NULL

/* ZUNIONSTORE destination argument */
#define ZUNIONSTORE_destination_Arg {"destination",ARG_TYPE_KEY,NULL,NULL,NULL,0,0,.value.string="destination"}

/* ZUNIONSTORE numkeys argument */
#define ZUNIONSTORE_numkeys_Arg {"numkeys",ARG_TYPE_INTEGER,NULL,NULL,NULL,0,0,.value.string="numkeys"}

/* ZUNIONSTORE key argument */
#define ZUNIONSTORE_key_Arg {"key",ARG_TYPE_KEY,NULL,NULL,NULL,0,1,.value.string="key"}

/* ZUNIONSTORE weights argument */
#define ZUNIONSTORE_weights_Arg {"weights",ARG_TYPE_INTEGER,"WEIGHTS",NULL,NULL,1,1,.value.string="weight"}

/* ZUNIONSTORE aggregate sum argument */
#define ZUNIONSTORE_aggregate_sum_Arg {"sum",ARG_TYPE_NULL,"SUM",NULL,NULL,0,0}

/* ZUNIONSTORE aggregate min argument */
#define ZUNIONSTORE_aggregate_min_Arg {"min",ARG_TYPE_NULL,"MIN",NULL,NULL,0,0}

/* ZUNIONSTORE aggregate max argument */
#define ZUNIONSTORE_aggregate_max_Arg {"max",ARG_TYPE_NULL,"MAX",NULL,NULL,0,0}

/* ZUNIONSTORE aggregate argument table */
struct redisCommandArg ZUNIONSTORE_aggregate_Subargs[] = {
ZUNIONSTORE_aggregate_sum_Arg,
ZUNIONSTORE_aggregate_min_Arg,
ZUNIONSTORE_aggregate_max_Arg,
{0}
};

/* ZUNIONSTORE aggregate argument */
#define ZUNIONSTORE_aggregate_Arg {"aggregate",ARG_TYPE_ONEOF,"AGGREGATE",NULL,NULL,1,0,.value.subargs=ZUNIONSTORE_aggregate_Subargs}

/* ZUNIONSTORE argument table */
struct redisCommandArg ZUNIONSTORE_Args[] = {
ZUNIONSTORE_destination_Arg,
ZUNIONSTORE_numkeys_Arg,
ZUNIONSTORE_key_Arg,
ZUNIONSTORE_weights_Arg,
ZUNIONSTORE_aggregate_Arg,
{0}
};

/* ZUNIONSTORE command */
#define ZUNIONSTORE_Command {"ZUNIONSTORE","Add multiple sorted sets and store the resulting sorted set in a new key","O(N)+O(M log(M)) with N being the sum of the sizes of the input sorted sets, and M being the number of elements in the resulting sorted set.","2.0.0",COMMAND_GROUP_SORTED_SET,ZUNIONSTORE_ReturnInfo,ZUNIONSTORE_History,zunionstoreCommand,-4,"write use-memory @sortedset @write @slow",{{"write",KSPEC_BS_INDEX,.bs.index={1},KSPEC_FK_RANGE,.fk.range={0,1,0}},{"read",KSPEC_BS_INDEX,.bs.index={1},KSPEC_FK_RANGE,.fk.keynum={0,1,1}}},zunionInterDiffStoreGetKeys,.args=ZUNIONSTORE_Args}

/********** XADD ********************/

/* XADD return info */
commandReturnInfo XADD_ReturnInfo[] = {
{"ID of the added entry",NULL,RETURN_TYPE_RESP2_3_SAME,.type.global=RESP2_BULK_STRING},
{"Stream doesn't exist and NOMKSTREAN was given",NULL,RETURN_TYPE_RESP2_3_DIFFER,.type.unique={RESP2_NULL_BULK_STRING,RESP3_NULL}},
{0}
};

/* XADD history */
commandHistory XADD_History[] = {
{"6.2","Added the `NOMKSTREAM` option, `MINID` trimming strategy and the `LIMIT` option."},
{0}
};

/* XADD key argument */
#define XADD_key_Arg {"key",ARG_TYPE_KEY,NULL,NULL,NULL,0,0,.value.string="key"}

/* XADD trimming strategy maxlen argument */
#define XADD_trimming_strategy_maxlen_Arg {"maxlen",ARG_TYPE_NULL,"MAXLEN",NULL,NULL,0,0}

/* XADD trimming strategy minid argument */
#define XADD_trimming_strategy_minid_Arg {"minid",ARG_TYPE_NULL,"MINID",NULL,"6.2.0",0,0}

/* XADD trimming strategy argument table */
struct redisCommandArg XADD_trimming_strategy_Subargs[] = {
XADD_trimming_strategy_maxlen_Arg,
XADD_trimming_strategy_minid_Arg,
{0}
};

/* XADD trimming strategy argument */
#define XADD_trimming_strategy_Arg {"strategy",ARG_TYPE_ONEOF,NULL,NULL,NULL,0,0,.value.subargs=XADD_trimming_strategy_Subargs}

/* XADD trimming operator exact argument */
#define XADD_trimming_operator_exact_Arg {"exact",ARG_TYPE_NULL,"=",NULL,NULL,0,0}

/* XADD trimming operator inexact argument */
#define XADD_trimming_operator_inexact_Arg {"inexact",ARG_TYPE_NULL,"~",NULL,NULL,0,0}

/* XADD trimming operator argument table */
struct redisCommandArg XADD_trimming_operator_Subargs[] = {
XADD_trimming_operator_exact_Arg,
XADD_trimming_operator_inexact_Arg,
{0}
};

/* XADD trimming operator argument */
#define XADD_trimming_operator_Arg {"operator",ARG_TYPE_ONEOF,NULL,NULL,NULL,1,0,.value.subargs=XADD_trimming_operator_Subargs}

/* XADD trimming threshold argument */
#define XADD_trimming_threshold_Arg {"threshold",ARG_TYPE_INTEGER,NULL,NULL,NULL,0,0,.value.string="threshold"}

/* XADD trimming limit argument */
#define XADD_trimming_limit_Arg {"limit",ARG_TYPE_INTEGER,"LIMIT",NULL,"6.2.0",1,0,.value.string="limit"}

/* XADD trimming argument table */
struct redisCommandArg XADD_trimming_Subargs[] = {
XADD_trimming_strategy_Arg,
XADD_trimming_operator_Arg,
XADD_trimming_threshold_Arg,
XADD_trimming_limit_Arg,
{0}
};

/* XADD trimming argument */
#define XADD_trimming_Arg {"trimming",ARG_TYPE_BLOCK,NULL,NULL,NULL,1,0,.value.subargs=XADD_trimming_Subargs}

/* XADD nomakestream argument */
#define XADD_nomakestream_Arg {"nomakestream",ARG_TYPE_NULL,"NOMKSTREAM",NULL,"6.2.0",1,0}

/* XADD id auto argument */
#define XADD_id_auto_Arg {"auto",ARG_TYPE_NULL,"*",NULL,NULL,0,0}

/* XADD id specific argument */
#define XADD_id_specific_Arg {"specific",ARG_TYPE_STRING,NULL,NULL,NULL,0,0,.value.string="ID"}

/* XADD id argument table */
struct redisCommandArg XADD_id_Subargs[] = {
XADD_id_auto_Arg,
XADD_id_specific_Arg,
{0}
};

/* XADD id argument */
#define XADD_id_Arg {"id",ARG_TYPE_ONEOF,NULL,NULL,NULL,0,0,.value.subargs=XADD_id_Subargs}

/* XADD fieldandvalues field argument */
#define XADD_fieldandvalues_field_Arg {"field",ARG_TYPE_STRING,NULL,NULL,NULL,0,0,.value.string="field"}

/* XADD fieldandvalues value argument */
#define XADD_fieldandvalues_value_Arg {"value",ARG_TYPE_STRING,NULL,NULL,NULL,0,0,.value.string="value"}

/* XADD fieldandvalues argument table */
struct redisCommandArg XADD_fieldandvalues_Subargs[] = {
XADD_fieldandvalues_field_Arg,
XADD_fieldandvalues_value_Arg,
{0}
};

/* XADD fieldandvalues argument */
#define XADD_fieldandvalues_Arg {"fieldandvalues",ARG_TYPE_BLOCK,NULL,NULL,NULL,0,1,.value.subargs=XADD_fieldandvalues_Subargs}

/* XADD argument table */
struct redisCommandArg XADD_Args[] = {
XADD_key_Arg,
XADD_trimming_Arg,
XADD_nomakestream_Arg,
XADD_id_Arg,
XADD_fieldandvalues_Arg,
{0}
};

/* XADD command */
#define XADD_Command {"XADD","Appends a new entry to a stream","O(1) when adding a new entry, O(N) when trimming where N being the number of entries evicted.","5.0.0",COMMAND_GROUP_STREAM,XADD_ReturnInfo,XADD_History,xaddCommand,-5,"write use-memory fast random @stream @write @slow",{{"write",KSPEC_BS_INDEX,.bs.index={1},KSPEC_FK_RANGE,.fk.range={0,1,0}}},.args=XADD_Args}

/********** SET ********************/

/* SET return info */
commandReturnInfo SET_ReturnInfo[] = {
{"Command succeeded","+OK",RETURN_TYPE_RESP2_3_SAME,.type.global=RESP2_SIMPLE_STRING},
{"Old value if `GET` was given",NULL,RETURN_TYPE_RESP2_3_SAME,.type.global=RESP2_BULK_STRING},
{"Either `SET` failed (with `NX` or `XX`), or `GET` was given and key didn't exist",NULL,RETURN_TYPE_RESP2_3_DIFFER,.type.unique={RESP2_NULL_BULK_STRING,RESP3_NULL}},
{0}
};

/* SET history */
commandHistory SET_History[] = {
{"2.6.12","Added the `EX`, `PX`, `NX` and `XX` options."},
{"6.0","Added the `KEEPTTL` option."},
{"6.2","Added the `GET`, `EXAT` and `PXAT` option."},
{"7.0","Allowed the `NX` and `GET` options to be used together."},
{0}
};

/* SET key argument */
#define SET_key_Arg {"key",ARG_TYPE_KEY,NULL,NULL,NULL,0,0,.value.string="key"}

/* SET value argument */
#define SET_value_Arg {"value",ARG_TYPE_STRING,NULL,NULL,NULL,0,0,.value.string="value"}

/* SET expire ex argument */
#define SET_expire_ex_Arg {"ex",ARG_TYPE_INTEGER,"EX",NULL,"2.6.12",0,0,.value.string="seconds"}

/* SET expire px argument */
#define SET_expire_px_Arg {"px",ARG_TYPE_INTEGER,"PX",NULL,"2.6.12",0,0,.value.string="milliseconds"}

/* SET expire exat argument */
#define SET_expire_exat_Arg {"exat",ARG_TYPE_UNIX_TIME,"EXAT",NULL,"6.2.0",0,0,.value.string="timestamp"}

/* SET expire pxat argument */
#define SET_expire_pxat_Arg {"pxat",ARG_TYPE_UNIX_TIME,"PXAT",NULL,"6.2.0",0,0,.value.string="milliseconds-timestamp"}

/* SET expire keepttl argument */
#define SET_expire_keepttl_Arg {"keepttl",ARG_TYPE_NULL,"KEEPTTL",NULL,"6.0.0",0,0}

/* SET expire argument table */
struct redisCommandArg SET_expire_Subargs[] = {
SET_expire_ex_Arg,
SET_expire_px_Arg,
SET_expire_exat_Arg,
SET_expire_pxat_Arg,
SET_expire_keepttl_Arg,
{0}
};

/* SET expire argument */
#define SET_expire_Arg {"expire",ARG_TYPE_ONEOF,NULL,NULL,NULL,1,0,.value.subargs=SET_expire_Subargs}

/* SET existence nx argument */
#define SET_existence_nx_Arg {"nx",ARG_TYPE_NULL,"NX",NULL,NULL,0,0}

/* SET existence xx argument */
#define SET_existence_xx_Arg {"xx",ARG_TYPE_NULL,"XX",NULL,NULL,0,0}

/* SET existence argument table */
struct redisCommandArg SET_existence_Subargs[] = {
SET_existence_nx_Arg,
SET_existence_xx_Arg,
{0}
};

/* SET existence argument */
#define SET_existence_Arg {"existence",ARG_TYPE_ONEOF,NULL,NULL,NULL,1,0,.value.subargs=SET_existence_Subargs}

/* SET get argument */
#define SET_get_Arg {"get",ARG_TYPE_NULL,"GET",NULL,"6.2.0",1,0}

/* SET argument table */
struct redisCommandArg SET_Args[] = {
SET_key_Arg,
SET_value_Arg,
SET_expire_Arg,
SET_existence_Arg,
SET_get_Arg,
{0}
};

/* SET command */
#define SET_Command {"SET","Set the string value of a key","O(1)","1.0.0",COMMAND_GROUP_STRING,SET_ReturnInfo,SET_History,setCommand,-3,"write use-memory @string @write @slow",{{"write",KSPEC_BS_INDEX,.bs.index={1},KSPEC_FK_RANGE,.fk.range={0,1,0}}},.args=SET_Args}

/* Main command table */
struct redisCommand redisCommandTable[] = {
/* generic */
CONFIG_Command,
MIGRATE_Command,
/* server */
COMMAND_Command,
/* sorted-set */
ZUNIONSTORE_Command,
/* stream */
XADD_Command,
/* string */
SET_Command,
{0}
};
