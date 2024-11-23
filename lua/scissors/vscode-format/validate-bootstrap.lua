local M = {}

local rw = require("scissors.vscode-format.read-write")
local u = require("scissors.utils")
--------------------------------------------------------------------------------

---@param snipDir string
---@return boolean
---@nodiscard
function M.validate(snipDir)
	-- empty filetype
	if vim.bo.filetype == "" then
		u.notify("`nvim-scissors` requires the current buffer to have a filetype.", "warn")
		return false
	end

	local snipDirInfo = vim.uv.fs_stat(snipDir)
	local packageJsonExists = u.fileExists(snipDir .. "/package.json")
	local isFriendlySnippetsDir = snipDir:find("/friendly%-snippets/")
		and not vim.startswith(snipDir, vim.fn.stdpath("config")) ---@diagnostic disable-line: param-type-mismatch

	-- snippetDir invalid
	if snipDirInfo and snipDirInfo.type ~= "directory" then
		u.notify(("%q is not a directory."):format(snipDir), "error")
		return false

	-- package.json invalid
	elseif snipDirInfo and packageJsonExists then
		local packageJson = rw.readAndParseJson(snipDir .. "/package.json")
		if
			vim.tbl_isempty(packageJson)
			or not (packageJson.contributes and packageJson.contributes.snippets)
		then
			u.notify(
				"The `package.json` in your `snippetDir` is invalid.\n"
					.. "Please make sure it follows the required specification for VSCode snippets.",
				"error"
			)
			return false
		end

	-- using friendly-snippets
	elseif isFriendlySnippetsDir then
		u.notify(
			"Snippets from `friendly-snippets` should be edited directly, since any changes would be overwritten as soon as the repo is updated.\n"
				.. "Copy the snippet files you want from the repo into your snippet directory and edit them there.",
			"error"
		)
		return false
	end

	return true
end

-- bootstrap if snippetDir and/or `package.json` do not exist
---@param snipDir string
function M.bootstrapSnipDir(snipDir)
	local snipDirExists = u.fileExists(snipDir)
	local packageJsonExists = u.fileExists(snipDir .. "/package.json")
	local msg = ""

	if not snipDirExists then
		local success = vim.fn.mkdir(snipDir, "p")
		assert(success == 1, snipDir .. " does not exist and could not be created.")
		msg = msg .. "Snippet directory does not exist. Creating one.\n"
	end
	if not packageJsonExists then
		local packageJsonStr = [[
{
	"contributes": {
		"snippets": []
	},
	"description": "This package.json has been generated by nvim-scissors.",
	"name": "my-snippets"
}
]]
		rw.writeFile(snipDir .. "/package.json", packageJsonStr)
		msg = msg .. "`package.json` does not exist. Bootstrapping one.\n"
	end

	if msg ~= "" then u.notify(vim.trim(msg)) end
end

---Write a new snippet file for the given filetype, update package.json, and
---returns the snipFile.
---@param ft string
---@param contents? string -- defaults to `{}`
---@return Scissors.snipFile -- the newly created snippet file
function M.bootstrapSnippetFile(ft, contents)
	local snipDir = require("scissors.config").config.snippetDir
	local newSnipName = ft .. ".json"

	-- create empty snippet file
	local newSnipFilepath
	while true do
		newSnipFilepath = snipDir .. "/" .. newSnipName
		if not u.fileExists(newSnipFilepath) then break end
		newSnipName = newSnipName .. "-1"
	end
	rw.writeFile(newSnipFilepath, contents or "{}")

	-- update package.json
	local packageJson = rw.readAndParseJson(snipDir .. "/package.json") ---@type Scissors.packageJson
	table.insert(packageJson.contributes.snippets, {
		language = { ft },
		path = "./" .. newSnipName,
	})
	rw.writeAndFormatSnippetFile(snipDir .. "/package.json", packageJson)

	-- return snipFile to directly add to it
	return { ft = ft, path = newSnipFilepath, fileIsNew = true }
end

--------------------------------------------------------------------------------
return M
