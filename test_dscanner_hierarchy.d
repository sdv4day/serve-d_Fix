/+ dub.sdl:
name "test_dscanner_hierarchy"
dependency "workspace-d" path="workspace-d"
+/

import std.stdio;
import workspaced.com.dscanner;

void main()
{
    string code = `
class l0
{
	class l1
	{
		class l23
		{
			int paoa;
			class l3{
				uint v3;
			}
			uint v2;
		}
		uint v1;
	}

	uint v0;
}
`;

    auto defs = listDefinitionsSync("test.d", code);
    writeln("Total definitions: ", defs.definitions.length);
    foreach (i, def; defs.definitions)
    {
        writeln(i, ": name=", def.name, ", containerName=", def.attributes.get("containerName", ""), ", range=", def.range);
    }
}
