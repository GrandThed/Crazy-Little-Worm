--!strict
-- Toolchain smoke test (F-2). Replace with real shared modules as features land.

local Hello = {}

function Hello.greet(context: string)
	print(("[CrazyLittleWorm] hello from %s"):format(context))
end

return Hello
