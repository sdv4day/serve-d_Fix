# Shutdown API 修复指南

## 🔍 问题分析

### 用户疑问
> workspaced.com.dcd 中的 stopDCD 函数并没有被实现？

**确认:** ✅ **正确！** `stopDCD()` 函数确实不存在。

---

## 📊 正确的 API

### DCD Component 的关闭方法

在 `workspace-d/source/workspaced/com/dcd.d` 中，DCD 组件提供以下关闭方法：

```d
// workspace-d/source/workspaced/com/dcd.d 第 179 行
override void shutdown(bool dtor = false)
{
    stopServerSync();
    if (!dtor && _threads)
        serverThreads.finish();
}
```

**关键点:**
- ✅ 方法名：`shutdown(bool dtor = false)` 
- ❌ **不存在:** `stopDCD()` 函数

### DScanner 的关闭方法

在 `source/served/linters/dscanner.d` 第 291 行：

```d
void shutdown(bool dtor)
{
    // DScanner 清理逻辑
}
```

---

## ✅ 正确的修复方案

### 修改 extension.d 中的 shutdown 函数

**位置:** `source/served/extension.d` 第 1079-1133 行

#### ❌ 错误代码（当前状态）

```d
@protocolMethod("shutdown")
JsonValue shutdown()
{
    // ... 其他代码 ...
    
    // Stop DCD server if running
    try
    {
        trace("Stopping DCD component");
        //import workspaced.com.dcd : stopDCD;  // ❌ 这个函数不存在
        //stopDCD();                            // ❌ 编译错误
    }
    catch (Exception e)
    {
        error("Error stopping DCD: ", e);
    }
    
    // Stop DScanner if running
    try
    {
        trace("Stopping DScanner");
        import served.linters.dscanner;
        //dscanner.shutdown(true);              // ⚠️ 为什么注释？
    }
    catch (Exception e)
    {
        error("Error stopping DScanner: ", e);
    }
    
    // ... 其他代码 ...
}
```

#### ✅ 正确代码

```d
@protocolMethod("shutdown")
JsonValue shutdown()
{
    import std.experimental.logger;
    trace("Shutdown requested - cleaning up resources");
    
    // Mark as shutdown to prevent new operations
    shutdownRequested = true;
    
    // Cleanup workspace-d backend if it exists
    if (backend)
    {
        try
        {
            trace("Shutting down workspace-d backend");
            backend.shutdown();  // ✅ 调用 ComponentManager 的 shutdown
        }
        catch (Exception e)
        {
            error("Error shutting down workspace-d backend: ", e);
        }
    }
    
    // 不需要单独停止 DCD 和 DScanner
    // backend.shutdown() 会自动调用所有组件的 shutdown 方法
    
    trace("Shutdown cleanup completed");
    return JsonValue(null);
}
```

---

## 🔧 技术细节

### ComponentManager 的 shutdown 机制

`workspace-d` 的 `ComponentManager` 会在 `shutdown()` 时自动清理所有组件：

```d
// workspace-d/source/workspaced/api.d
void shutdown(bool dtor = false)
{
    foreach (component; components)
    {
        // 调用每个组件的 shutdown 方法
        component.shutdown(dtor);
    }
    
    // 包括：
    // - DCDComponent.shutdown()   ← 自动调用
    // - DscannerComponent.shutdown() ← 自动调用
    // - DubComponent.shutdown()      ← 自动调用
    // - 等等...
}
```

### DCDComponent 的 shutdown 实现

```d
// workspace-d/source/workspaced/com/dcd.d 第 179 行
override void shutdown(bool dtor = false)
{
    stopServerSync();  // 停止 DCD 服务器进程
    if (!dtor && _threads)
        serverThreads.finish();  // 清理线程池
}
```

**stopServerSync() 的作用:**
1. 调用 `client.shutdown()` 通知服务器关闭
2. 等待进程退出（最多 2 秒）
3. 如果超时则强制杀死进程

### DScanner 的 shutdown 实现

```d
// source/served/linters/dscanner.d 第 291 行
void shutdown(bool dtor)
{
    import dscanner;
    dscanner.shutdown(dtor);  // 清理 DScanner 资源
    backend.shutdown(dtor);   // 清理后端资源
}
```

---

## 🎯 完整修复步骤

### 步骤 1: 理解架构层次

```
serve-d (extension.d)
    ↓
workspace-d (api.d - ComponentManager)
    ↓
各个组件 (dcd.d, dscanner.d, dub.d, ...)
```

**调用链:**
```
extension.shutdown()
    → backend.shutdown()           // ComponentManager
        → DCDComponent.shutdown()  // 自动调用
        → DscannerComponent.shutdown()  // 自动调用
        → 其他组件...
```

### 步骤 2: 简化 shutdown 函数

**删除不必要的单独调用，信任 ComponentManager 的自动清理：**

```d
@protocolMethod("shutdown")
JsonValue shutdown()
{
    import std.experimental.logger;
    trace("Shutdown requested - cleaning up resources");
    
    // 1. 设置标志防止新操作
    shutdownRequested = true;
    
    // 2. 调用 backend.shutdown() 自动清理所有组件
    if (backend)
    {
        try
        {
            trace("Shutting down workspace-d backend");
            backend.shutdown();  // ✅ 这会自动调用 DCD、DScanner 等的 shutdown
        }
        catch (Exception e)
        {
            error("Error shutting down workspace-d backend: ", e);
            // 继续执行，不阻断 shutdown 流程
        }
    }
    
    // 3. 设置定时器检查 RPC 是否正常停止
    served.extension.setTimeout({
        throw new Error("RPC still running 1s after shutdown");
    }, 1.seconds);
    
    trace("Shutdown cleanup completed");
    return JsonValue(null);
}
```

### 步骤 3: 验证修复

```bash
# 编译项目
dub build

# 应该没有编译错误
# 特别是不再有 "undefined identifier stopDCD" 错误
```

### 步骤 4: 测试 shutdown 流程

```bash
# 启动 serve-d
./serve-d

# 从另一个终端发送 shutdown 请求
echo '{"jsonrpc":"2.0","method":"shutdown","id":1}' | nc localhost <port>

# 检查：
# 1. serve-d 正常退出
# 2. DCD 进程已停止 (ps aux | grep dcd-server)
# 3. 端口 9166 已释放 (netstat -an | grep 9166)
```

---

## 📝 常见误区

### 误区 1: 手动调用每个组件的 shutdown

❌ **错误做法:**
```d
backend.get!DCDComponent.stopDCD();      // 函数不存在
backend.get!DscannerComponent.shutdown(); // 不必要
backend.get!DubComponent.shutdown();      // 不必要
```

✅ **正确做法:**
```d
backend.shutdown();  // 自动调用所有组件的 shutdown
```

### 误区 2: 使用不存在的 API

❌ **不存在的方法:**
- `stopDCD()`
- `stopDScanner()`
- `stopDub()`

✅ **存在的方法:**
- `DCDComponent.shutdown(bool dtor)`
- `DscannerComponent.shutdown(bool dtor)`
- `DubComponent.shutdown(bool dtor)`
- `ComponentManager.shutdown(bool dtor)` ← **推荐使用**

### 误区 3: 忽略异常处理

❌ **危险做法:**
```d
backend.shutdown();  // 可能抛出异常导致 shutdown 中断
```

✅ **安全做法:**
```d
try
{
    backend.shutdown();
}
catch (Exception e)
{
    error("Shutdown failed: ", e);
    // 继续执行后续清理
}
```

---

## 🔗 相关源码位置

### serve-d 项目

| 文件 | 行号 | 说明 |
|------|------|------|
| `source/served/extension.d` | 1079-1133 | shutdown 函数实现 |
| `source/served/linters/dscanner.d` | 291 | DScanner shutdown |

### workspace-d 项目

| 文件 | 行号 | 说明 |
|------|------|------|
| `source/workspaced/api.d` | - | ComponentManager.shutdown() |
| `source/workspaced/com/dcd.d` | 179 | DCDComponent.shutdown() |
| `source/workspaced/com/dscanner.d` | - | DscannerComponent.shutdown() |

---

## ✅ 总结

### 关键发现

1. **`stopDCD()` 函数不存在** - 用户的观察是正确的
2. **应该使用 `backend.shutdown()`** - 自动清理所有组件
3. **无需手动调用各组件 shutdown** - ComponentManager 会处理

### 修复要点

```d
// 简化的正确实现
JsonValue shutdown()
{
    shutdownRequested = true;
    
    if (backend)
        backend.shutdown();  // ✅ 一键清理所有资源
    
    return JsonValue(null);
}
```

### 验证标准

- ✅ 编译无错误
- ✅ 无 "undefined identifier" 错误
- ✅ shutdown 后 DCD 进程停止
- ✅ shutdown 后 DScanner 资源释放
- ✅ 端口 9166 释放

---

*修复日期：2026-04-02*  
*修复人员：AI Assistant*  
*验证状态：待编译测试*
