-----------------------------------------------------------------------
-- Quest2RareScanner locale
-----------------------------------------------------------------------

local ADDON_NAME, ns = ...

local L = {
    HELP_TITLE = "Quest2RareScanner 0.1.0",
    HELP_MAP = "世界地图：Alt+左键点击 Questie 图标，把对应 NPC 加入 RareScanner。",
    HELP_GROUP = "NPC 会放进 Q2RS_<任务ID> 组；手动标记进 Q2RS_手动。",
    HELP_CMD = "/q2rs - 显示帮助和状态；/q2rs delete - 删除所有已添加的 NPC",
    HELP_DEBUG = "/q2rs debug - 输出 Q2RS 组/NPC 状态",
    RECENTLY_SEEN_HINT = "提示：已给删除的 NPC 设置临时过滤以立即隐藏图标；RareScanner 的“最近目击”标记最多保留 2 分钟（副本 30 分钟）。如果还有图标，等一会或 /reload。",
    IMPORTED = "已提交 %d 个 NPC 到 RareScanner（组 %s）：",
    NO_RARESCANNER = "RareScanner 未加载或导入命令不可用。",
    IMPORT_ERROR = "导入失败：",
    STATUS = "Questie: %s | RareScanner: %s | 地图图标 hook: %s | 坐标: %s",
    READY = "就绪",
    NOT_READY = "未就绪",
    ALT_HINT = "Alt+左键：加入 RareScanner",
    POS_PATROL = "巡逻 %d 条路径",
    POS_MULTI = "已知%d个刷新地点",
    POS_FIXED = "固定单点",
    POS_UNKNOWN = "位置未知",
    LOAD_ERROR_QUESTIE = "需要 Questie + QuestieDB，当前未加载。",
    LOAD_ERROR_DB = "QuestieDB (LibQuestieDB) 未加载，无法解析 NPC 数据。",
    ZONE_NOT_READY = "Questie ZoneDB 未加载，坐标会写 *。",
    HOOK_ERROR = "Questie 图标 hook 失败，请检查 Questie 版本。",
    BUTTON_TITLE = "Quest2RareScanner",
    BUTTON_LEFT = "左键：删除所有已添加的 NPC",
    BUTTON_RIGHT = "右键：帮助/状态",
    BUTTON_DRAG = "拖动：调整位置",
    BUTTON_COUNT = "当前：%d 个 NPC，%d 个组",
    DELETE_CONFIRM = "删除 Quest2RareScanner 添加的所有 NPC？\n\n%d 个 NPC，%d 个组。",
    DELETE_NONE = "没有找到 Q2RS_ 组，无需删除。",
    DELETE_IN_COMBAT = "战斗中不能删除，请脱离战斗后再试。",
    DELETE_NO_RARESCANNER = "RareScanner 未加载，无法删除。",
    DELETE_DONE = "已删除 %d 个组（原来 %d 个 NPC）。",
    DELETE_PARTIAL = "部分组无法通过 RareScanner 接口删除，已从存档清理，请 /reload 生效。",
    DELETE_FAILED = "删除失败：%s",
    REFRESHING = "正在刷新 RareScanner 地图图标…",
    AUTO_REMOVED = "任务「%s」：自动移除 %d 个追踪 NPC%s。",
    AUTO_KEPT = "（保留任务交付 NPC %d 个）",
    AUTO_GIVERS_REMOVED = "任务「%s」：自动移除 %d 个任务给予者。",
    AUTO_GROUP_REMOVED = "任务「%s」：已移除整组（%d 个 NPC）。",
    START_ITEM_CLEANED = "任务「%s」：已清理 %d 个起始物品掉落来源。",
    LOG_NO_QUEST = "这个任务已经不在任务日志里。",
    LOG_NO_NPCS = "这个任务没有可加入的 NPC。",
    LOG_ADD_IN_COMBAT = "战斗中不能加入追踪，请脱离战斗后再试。",
    QUEST_LOG_ADDED = "任务「%s」：已提交 %d 个 NPC（击杀 / 掉落目标 %d，任务交付 %d）。",
    CLEANUP_RELOAD = "部分数据无法通过 RareScanner 接口删除，已从存档清理，请 /reload 生效。",
}


ns.L = L
