module served.commands.symbol_search;

import served.extension;
import served.types;

import mir.serde;

import workspaced.api;
import workspaced.coms;
import workspaced.com.dscanner : DefinitionElement;
import workspaced.com.index;

import std.algorithm : among, canFind, filter, map;
import std.array : appender, array, join;
import std.path : extension, isAbsolute;
import std.string : toLower;

import fs = std.file;
import io = std.stdio;

@protocolMethod("workspace/symbol")
SymbolInformation[] provideWorkspaceSymbols(WorkspaceSymbolParams params)
{
	import fuzzymatch;

	auto infos = appender!(SymbolInformation[]);
	foreach (workspace; workspaces)
	{
		auto folderPath = workspace.folder.uri.uriToFile;
		if (workspace.config.d.enableIndex && backend.has!IndexComponent(folderPath))
		{
			auto indexer = backend.get!IndexComponent(folderPath);
			indexer.iterateAll(delegate(ModuleRef mod, string fileName, scope const ref DefinitionElement def) {
				if (def.isImportable
					&& !mod.isStdLib
					&& def.name.fuzzyMatchesString(params.query))
				{
					Position p;
					p.line = def.line - 1;
					auto info = makeSymbolInfoEx(def, fileName.uriFromFile, p, p).downcast;
					if (info.containerName.isNone)
						info.containerName = mod;
					infos ~= info;
				}
			});
		}
	}
	return infos.data;
}

@protocolMethod("textDocument/documentSymbol")
JsonValue provideDocumentSymbols(DocumentSymbolParams params)
{
	if (capabilities
		.textDocument.orDefault
		.documentSymbol.orDefault
		.hierarchicalDocumentSymbolSupport.orDefault)
		return provideDocumentSymbolsHierarchical(params).toJsonValue;
	else
		return provideDocumentSymbolsOld(DocumentSymbolParamsEx(params, true)).map!"a.downcast".array.toJsonValue;

}

private struct OldSymbolsCache
{
	SymbolInformationEx[] symbols;
	SymbolInformationEx[] symbolsVerbose;
}

PerDocumentCache!OldSymbolsCache documentSymbolsCacheOld;
SymbolInformationEx[] provideDocumentSymbolsOld(DocumentSymbolParamsEx params)
{
	if (!backend.hasBest!DscannerComponent(params.textDocument.uri.uriToFile))
		return null;

	auto cached = documentSymbolsCacheOld.cached(documents, params.textDocument.uri);
	if (cached.symbolsVerbose.length)
		return params.verbose ? cached.symbolsVerbose : cached.symbols;
	auto document = documents.tryGet(params.textDocument.uri);
	if (document.getLanguageId != "d")
		return null;

	auto result = backend.best!DscannerComponent(params.textDocument.uri.uriToFile)
		.listDefinitions(uriToFile(params.textDocument.uri), document.rawText, true).getYield
		.definitions;
	auto ret = appender!(SymbolInformationEx[]);
	auto retVerbose = appender!(SymbolInformationEx[]);

	size_t cacheByte = size_t.max;
	Position cachePosition;

	foreach (def; result)
	{
		auto startPosition = document.movePositionBytes(cachePosition, cacheByte, def.range[0]);
		auto endPosition = document.movePositionBytes(startPosition, def.range[0], def.range[1]);
		cacheByte = def.range[1];
		cachePosition = endPosition;

		auto info = makeSymbolInfoEx(def, params.textDocument.uri, startPosition, endPosition);
		if (!def.isVerboseType)
			ret.put(info);
		retVerbose.put(info);
	}
	documentSymbolsCacheOld.store(document, OldSymbolsCache(ret.data, retVerbose.data));

	return params.verbose ? retVerbose.data : ret.data;
}

SymbolInformationEx makeSymbolInfoEx(scope const ref DefinitionElement def, DocumentUri uri, Position startPosition, Position endPosition)
{
	SymbolInformationEx info;
	info.name = def.name;
	info.location.uri = uri;
	info.location.range = TextRange(startPosition, endPosition);
	info.kind = convertFromDscannerType(def.type, def.name);
	info.extendedType = convertExtendedFromDscannerType(def.type);
	if (auto cname = "struct" in def.attributes)
		if (info.containerName.length == 0) info.containerName = *cname;
	if (auto cname = "enum" in def.attributes)
		if (info.containerName.length == 0) info.containerName = *cname;
	if (auto cname = "class" in def.attributes)
		if (info.containerName.length == 0) info.containerName = *cname;
	if (auto cname = "interface" in def.attributes)
		if (info.containerName.length == 0) info.containerName = *cname;
	if (auto cname = "union" in def.attributes)
		if (info.containerName.length == 0) info.containerName = *cname;

		// 使用 DefinitionElement 中的 containerName（父符号名称）
	//info.containerName = def.containerName; // corrected field name
	if ("deprecation" in def.attributes)
		info.tags = [SymbolTag.deprecated_];
	if (auto signature = "signature" in def.attributes)
		info.detail = *signature;
	if (auto detail = "detail" in def.attributes)
		info.detail = *detail;
	return info;
}

@serdeProxy!DocumentSymbol
struct DocumentSymbolInfo
{
	DocumentSymbol symbol;
	string parent;
	alias symbol this;
	int[] childIndices;  // 存储子节点在all数组中的索引
}

PerDocumentCache!(DocumentSymbolInfo[]) documentSymbolsCacheHierarchical;
DocumentSymbolInfo[] provideDocumentSymbolsHierarchical(DocumentSymbolParams params)
{
	auto cached = documentSymbolsCacheHierarchical.cached(documents, params.textDocument.uri);
	if (cached.length)
		return cached;
	DocumentSymbolInfo[] all;
	auto symbols = provideDocumentSymbolsOld(DocumentSymbolParamsEx(params, true));
	foreach (symbol; symbols)
	{
		DocumentSymbolInfo sym;
		static foreach (member; __traits(allMembers, SymbolInformationEx))
			static if (__traits(hasMember, DocumentSymbolInfo, member))
				__traits(getMember, sym, member) = __traits(getMember, symbol, member);
		sym.parent = symbol.containerName;
		sym.range = sym.selectionRange = symbol.location.range;
		sym.selectionRange.end.line = sym.selectionRange.start.line;
		if (sym.selectionRange.end.character < sym.selectionRange.start.character)
			sym.selectionRange.end.character = sym.selectionRange.start.character;
		all ~= sym;
	}

	// 使用范围构建层级结构
	// 规则：如果一个符号的范围完全在另一个符号的范围内，则它是另一个符号的子级
	// 选择直接父级（最小的包含范围）
	
	// 辅助函数：检查a是否包含b（a的范围完全包含b的范围）
	static bool contains(ref DocumentSymbolInfo a, ref DocumentSymbolInfo b)
	{
		// 检查起始位置
		if (a.range.start.line > b.range.start.line)
			return false;
		if (a.range.start.line == b.range.start.line && a.range.start.character > b.range.start.character)
			return false;
		// 检查结束位置
		if (a.range.end.line < b.range.end.line)
			return false;
		if (a.range.end.line == b.range.end.line && a.range.end.character < b.range.end.character)
			return false;
		return true;
	}
	
	// 第一步：为每个符号找到其直接父级（范围最小的直接包含者）并记录子关系
	foreach (i, ref sym; all)
	{
		DocumentSymbolInfo* bestParent = null;
		int bestParentIndex = -1;
		
		foreach (j, ref other; all)
		{
			// 跳过自己
			if (i == j)
				continue;
			
			// 检查other的范围是否完全包含sym的范围
			if (contains(other, sym))
			{
				// 选择最小的包含范围（最直接的父级）
				if (bestParent is null)
				{
					bestParent = &other;
					bestParentIndex = cast(int)j;
				}
				else if (contains(*bestParent, other))
				{
					// other在bestParent内部，所以other是更直接的父级
					bestParent = &other;
					bestParentIndex = cast(int)j;
				}
			}
		}
		
		// 如果找到了父级，记录子关系（使用索引而非拷贝）
		if (bestParentIndex >= 0)
		{
			all[bestParentIndex].childIndices ~= cast(int)i;
		}
	}
	
	// 第二步：从叶子节点向上递归构建DocumentSymbol树
	DocumentSymbol buildSymbolTree(int index)
	{
		DocumentSymbol result = all[index].symbol;  // 拷贝基础信息
		result.children = null;  // 清空children，重新构建
		
		// 递归构建子节点
		foreach (childIdx; all[index].childIndices)
		{
			result.children ~= buildSymbolTree(childIdx);
		}
		
		return result;
	}
	
	// 第三步：找到所有顶层节点并构建最终的层级结构
	DocumentSymbolInfo[] ret;
	foreach (i, ref sym; all)
	{
		bool hasParent = false;
		foreach (j, ref other; all)
		{
			if (i != j && contains(other, sym))
			{
				hasParent = true;
				break;
			}
		}
		if (!hasParent)
		{
			// 这是顶层节点，构建完整的子树
			DocumentSymbolInfo topNode;
			topNode.symbol = buildSymbolTree(cast(int)i);
			topNode.parent = sym.parent;
			ret ~= topNode;
		}
	}
	
	documentSymbolsCacheHierarchical.store(documents.tryGet(params.textDocument.uri), ret);
	
	// 调试输出：打印最终层级树
	io.writeln("=== DEBUG HIERARCHY ===");
	void printTree(DocumentSymbol[] symbols, int indent = 0)
	{
		foreach (sym; symbols)
		{
			foreach (_; 0 .. indent) io.write("  ");
			io.writeln(sym.name, " (", sym.children.length, " children)");
			printTree(sym.children, indent + 1);
		}
	}
	DocumentSymbol[] topLevelSymbols;
	foreach (sym; ret) topLevelSymbols ~= sym.symbol;
	printTree(topLevelSymbols);
	io.writeln("=== END HIERARCHY ===");
	
	return ret;
}
