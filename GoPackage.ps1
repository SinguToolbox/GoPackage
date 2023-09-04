<#
.SYNOPSIS
Go 程序自动打包脚本（v1.0.0）

.DESCRIPTION
涵盖了编译、压缩、打包等一系列操作的自动化脚本，支持跨平台交叉编译。
作者：Singu (singu@singu.top)
版本：v1.0.0

.PARAMETER Publish
发布模式，若为开启该选项时，脚本默认以调试模式执行；

.PARAMETER CrossPlatform
开启跨平台编译，默认为 false；
为 true 时，将会编译全平台版本的程序包。

.PARAMETER TargetSystem
指定目标操作系统，默认为当前主机操作系统；
当 CrossPlatform 有值时，该项无效；

.PARAMETER TargetArch
指定目标 CPU 架构，默认为当前主机 CPU 架构；
当 CrossPlatform 有值时，该项无效；
当 TargetSystem 无值时，该项无效；

.PARAMETER ForceCompress
强制压缩可执行程序，当处于调试模式下时，该项默认为 false；当处于发布模式下时，该项恒定为 true；
若该项为 true，则会对编译后的可执行程序进行无损压缩（依赖 UPX）。
UPX：https://upx.github.io

.PARAMETER ForcePackage
强制打包程序，当处于调试模式下时，该项默认为 false；当处于发布模式下时，该项恒定为 true；
若该项为 true，则会将编译后的可执行程序及相关输出文件打包到压缩包中。

.PARAMETER Unclear
默认情况下，脚本执行完成后会自动清理编译输出目录，开启该项后，脚本将不再清理编译时产生的文件及目录。

.PARAMETER ContinueLastBuild
默认情况下，脚本会在每次执行时，清除上次执行时产生的所有文件，开启该项后，脚本将不再清理上次构建产生的文件，而是继续上次构建的结果再次进行构建。

.PARAMETER Version
程序版本号，当处于发布模式下时必须指定该项；
版本号的正则表达式规则为：v\d+(\.\d+)*(-\w+)?
例如：v1.0、v1.0.0、v1.0.0-alpha

.EXAMPLE
.\GoPackage.ps1
构建本地调试版本程序包

.EXAMPLE
.\GoPackage.ps1 -Publish -Version "v1.0"
构建本地程序发布包

.EXAMPLE
.\GoPackage.ps1 -Publish -CrossPlatform -Version "v1.0"
构架跨平台程序发布包

.LINK
UPX: https://upx.github.io
#>



<# 声明脚本参数 #>
param(
    ## 发布模式
    [Switch]
    $Publish,
    ## 跨平台编译
    [Switch]
    $CrossPlatform,
    ## 目标系统
    [ValidateSet("Windows", "Win", "Linux", "MacOS", "Darwin", IgnoreCase=$true)]
    [string]
    $TargetSystem,
    ## 目标架构
    [string]
    $TargetArch,
    ## 强制压缩可执行程序
    # 该项仅对调试模式生效，默认情况下调试模式不执行可执行程序压缩，通过开启该项配置，可以在调试模式下强制压缩可执行程序；
    # 在发布模式下，该项恒定为 true
    [Switch]
    $ForceCompress,
    ## 强制打包
    # 该项仅对调试模式生效，默认情况下调试模式不执行打包流程，通过开启该项配置，可以在调试模式下强制进行打包；
    # 在发布模式下，该项恒定为 true
    [Switch]
    $ForcePackage,
    ## 不清理构建输出
    # 默认情况下，脚本执行完成后会自动清理编译输出目录，开启该项后，脚本将不再清理编译时产生的文件及目录；
    [Switch]
    $Unclear,
    ## 继续上次构建
    # 默认情况下，脚本会在每次执行时，清除上次执行时产生的所有文件，开启该项后，脚本将不再清理上次构建产生的文件，而是继续上次构建的结果再次进行构建。
    [Switch]
    $ContinueLastBuild,
    ## 程序版本号
    [ValidatePattern("v\d+(\.\d+)*(-\w+)?")]
    [string]
    $Version
)




<#
声明用户自定义常量
  首次使用脚本前，一定要修改此处的变量
#>

# 主模块名称
## 主程序的 GoModule 名称，该项留空时会取当前脚本所在目录的名称
[string]$ModuleName = ""

# 源码目录
## 源代码存放路径，一般对应 src 文件夹
## 该项留空时会取当前脚本所在目录
## 为 '.' 时与留空等价
[string]$SourceDirPath = "src"

# 输出相对路径
[string]$OutputRelativePath = ""

# 构建目标类型
## 为 0 时，表示仅构建可执行程序
## 为 1 时，表示仅构建动态链接库
## 为 2 时，表示构建可执行程序与动态链接库
[int]$BuildTargetType = 0

# 允许构建的操作系统集合
## 为空表示不限制任何操作系统
## 必须以全小写格式书写
## MacOS 系统必须写为 darwin
$AllowSystems = @()

# 允许构建的架构类型集合
## 为空表示不限制任何架构类型
## 必须以全小写格式书写
## x32, x86, i386 架构必须写为 386
## x64 架构必须写为 amd64
$AllowArches = @()

# 其他文件列表
## 在此处声明的文件将会在打包时复制到打包输出目录下
$OutputFiles = @{
    # "<原文件路径，相对于脚本所在目录>" = "<存放路径，相对于输出路径>"
}




<#
声明用户扩展常量
  若无必要，请勿修改此处的常量值
#>

# 程序名称
[string]$ProgramName = ""

# 自定义扩展名
## 为空时将采用默认扩展名
## 仅对可执行程序生效，动态链接库不受影响
[string]$CustomExtension = ""

# 构建目录
[string]$BuildDirName = "build"

# 输出目录
[string]$DistDirName = "dist"

# 编译扩展命令
[string]$CompileExtParams = ""

# 可执行程序编译扩展命令
[string]$CompileExtParamsForExecution = ""

# 动态链接库编译扩展命令
[string]$CompileExtParamsForDynamicLinkLibrary = ""

# 压缩扩展参数
[string]$CompressExtParams = ""

# 可执行程序压缩扩展命令
[string]$CompressExtParamsForExecution = ""

# 动态链接库压缩扩展命令
[string]$CompressExtParamsForDynamicLinkLibrary = ""



<# 声明运行时变量 #>

## 脚本所在目录
[string]$ScriptParentPath = $(Split-Path -Parent $MyInvocation.MyCommand.Definition)

## 执行模式
# 0: 发布模式
# 1: 调试模式
[int]$Mode = 1
If ($Publish) {
    $Mode = 0
}

## 标准模式
# 若源代码结构采用的是标准的 GOPATH 结构（即 src/your/package/name），则该项为 true
# 若该项为 true，则采用 `go build src/your/package/name` 方式打包，
# 否则采用 `cd source/path && go build . && cp exefile dist/path` 方式打包。
[bool]$StandardMode = $true
If (Test-Path -Path "$ScriptParentPath/$SourceDirPath/go.mod") {
    $StandardMode = $false
}

## 系统名称映射
$SystemNameMapping = @{
    # Windows
    win = "windows"
    windows = "windows"
    # Linux
    linux = "linux"
    ubuntu = "linux"
    centos = "linux"
    # MacOS
    macos = "darwin"
    darwin = "darwin"
}

## 架构名称映射
$ArchNameMapping = @{
    # 386
    "386" = "386"
    i386 = "386"
    x32 = "386"
    x86 = "386"
    # Amd64
    amd64 = "amd64"
    x64 = "amd64"
    "x86-64" = "amd64"
    "x86_64" = "amd64"
    # Arm
    arm = "arm"
    # Arm64
    arm64 = "arm64"
}

## 跨平台支持列表
$SupportList = @{
    windows = @(
        "386",
        "amd64",
        "arm",
        "arm64"
    );
    linux = @(
        "386",
        "amd64",
        "arm",
        "arm64"
    );
    darwin = @(
        "amd64",
        "arm64"
    );
}

## 格式化名称
$FormatNames = @{
    # 操作系统
    windows = "Windows"
    linux = "Linux"
    darwin = "MacOS"
    # CPU 架构
    "386" = "x32"
    amd64 = "x64"
    arm = "Arm"
    arm64 = "Arm64"
}

## 检查 UPX 是否存在
[bool]$HasUPX = $true
Try {
    $UselessOutput = $(Get-Command -Name upx)
}
Catch {
    $HasUPX = $false
    # 若当前处于 Publish 模式下，则发出警告
    If ($Mode -eq 0) {
        $(Write-Warning -Message "未找到 UPX 程序，将忽略可执行程序压缩流程")
    }
    # 若开启了 ForceCompress，则发出错误，并结束程序
    ElseIf ($ForceCompress) {
        Write-Error -Message "未找到 UPX 程序，无法完成可执行程序压缩流程，若您仍然想要编译，请关闭 ForceCompress"
        Exit 1
    }
}





<# 声明函数 #>

# 参数检查
Function CheckParameters () {
    # 若当前处于发布模式或启用了强制打包功能，则必须指定版本号
    If (($Publish -or $ForcePackage) -and ($Version.Length -eq 0)) {
        throw "发布模式下，或启用了强制打包功能时，必须指定版本号！"
    }
}

# 准备
Function Prepare {
    # 若模块名称留空，则取当前所在目录的名称
    If ($ModuleName.Length -eq 0) {
        $ModuleName = $(Split-Path -Leaf $ScriptParentPath)
    }
    # 启用 Go Module
    $Env:GO111MODULE = "on"
    # 关闭 CGO
    $Env:CGO_ENABLED = 0
    # 若未声明需要继续上次的构建，则清理上次执行时产生的所有文件
    If (-not $ContinueLastBuild) {
        # 删除上次执行时构建程序产生的文件
        If (Test-Path -Path "$ScriptParentPath/$BuildDirName") {
            Remove-Item -Force -Recurse -Path "$ScriptParentPath/$BuildDirName"
        }
        # 删除上次执行时输出的程序包
        If (Test-Path -Path "$ScriptParentPath/$DistDirName") {
            Remove-Item -Force -Recurse -Path "$ScriptParentPath/$DistDirName"
        }
    }
    # 若当前处于发布模式，或者开启了强制打包功能，则创建程序包输出目录
    If ($Publish -or $ForcePackage) {
        $UselessOutput = $(New-Item -Force -ItemType Directory -Path "$ScriptParentPath/$DistDirName")
    }
    # 进入源代码目录
    If ($StandardMode) {
        Set-Location -Path "$SourceDirPath/$ModuleName"
    }
    Else {
        Set-Location -Path $SourceDirPath
    }
    # 验证依赖
    Write-Output "正在验证程序包依赖..."
    $UselessOutput = $(go mod verify)
    If (-not $?) {
        Write-Error "模块依赖验证不通过"
        Exit 1
    }
    # 更新依赖
    Write-Output "正在更新程序包依赖..."
    $UselessOutput = $(go mod download all)
    # 检查是否编译成功
    If (-not $?) {
        Write-Error "模块依赖更新失败"
        Exit 1
    }
    ## 回到脚本所在目录
    Set-Location -Path $ScriptParentPath
    # 若程序名称为空串，则取主模块名称最后一段
    If ($ProgramName.Length -eq 0) {
        $script:ProgramName = Split-Path -Leaf $ModuleName
    }
}


# 编译
Function Compile ([string]$System, [string]$Arch) {
    ## 设置当前环境参数
    # 当前编译的系统
    $Env:GOOS = $System
    # 当前编译的架构
    $Env:GOARCH = $Arch

    ## 设置输出目录
    $OutputDirPath = "$BuildDirName/$System-$Arch/$ProgramName"
    # 若输出相对路径不为空，则补充输出相对路径
    If ($OutputRelativePath -ne "") {
        $OutputDirPath += "/$OutputRelativePath"
    }
    ## 设置输出程序文件名
    $OutputProgramName = $ProgramName

    ## 设置可执行程序扩展名
    $ExectionExtension = ""
    # 若设置了自定义扩展名，则取自定义扩展名
    If ($CustomExtension -ne "") {
        $ExectionExtension = $CustomExtension
    }
    # 若当前正在编译 Windows 程序，则补充可执行程序后缀名
    ElseIf ($System -eq "windows") {
        $ExectionExtension = ".exe"
    }
    ## 可执行程序输出文件名
    $OutputProgramNameForExection += $ExectionExtension

    ## 设置动态链接库扩展名
    $DynamicLinkLibraryExtension = ""
    # 若当前正在编译 Windows 程序，则为 '.dll'
    If ($System -eq "windows") {
        $DynamicLinkLibraryExtension = ".dll"
    }
    # 否则为 '.so'
    Else {
        $DynamicLinkLibraryExtension = ".so"
    }
    ## 动态链接库输出文件名
    $OutputProgramNameForDynamicLinkLibrary += $DynamicLinkLibraryExtension

    ## 创建输出目录
    If (-not (Test-Path -Path $OutputDirPath)) {
        $UselessOutput = $(New-Item -Force -ItemType Directory -Path $OutputDirPath)
    }

    ## 构建编译命令
    # 构建可执行程序基本命令
    $CompileCommandForExection = "go build -a -o `"$ScriptParentPath/$OutputDirPath/$OutputProgramNameForExection`""
    # 构建动态链接库基本命令
    $CompileCommandForDynamicLinkLibrary = "go build -a -o `"$ScriptParentPath/$OutputDirPath/$OutputProgramNameForDynamicLinkLibrary`""
   
    # 根据执行模式，拼接命令
    Switch ($Mode) {
        0 {
            ## 发布模式
            $CompileCommandForExection += " -trimpath"
            $CompileCommandForDynamicLinkLibrary += " -trimpath"
        }
    }
    # 追加扩展参数
    If ($CompileExtParams.Length -ne 0) {
        $CompileCommandForExection += " " + $CompileExtParams
        $CompileCommandForDynamicLinkLibrary += " " + $CompileExtParams
    }
    If ($CompileExtParamsForExecution.Length -ne 0) {
        $CompileCommandForExection += " " + $CompileExtParamsForExecution
    }
    If ($CompileExtParamsForDynamicLinkLibrary.Length -ne 0) {
        $CompileCommandForDynamicLinkLibrary += " " + $CompileExtParamsForDynamicLinkLibrary
    }
    # 追加包名称
    If ($StandardMode) {
        # 标准模式下，直接追加包名
        $CompileCommandForExection += " " + $ModuleName
        $CompileCommandForDynamicLinkLibrary += " " + $ModuleName
    }
    Else {
        # 非标准模式下，以 '.' 作为包名
        $CompileCommandForExection += " ."
        $CompileCommandForDynamicLinkLibrary += " ."
    }

    ## 执行编译
    If ($BuildTargetType -eq 0 -or $BuildTargetType -eq 2) {
        # 输出日志
        Write-Debug "`<$System`:$Arch`> 编译命令：[$CompileCommandForExection]"
        # 进入源码目录
        Set-Location -Path $SourceDirPath
        # 执行编译命令
        Invoke-Expression "$CompileCommandForExection"
        # 检查是否编译成功
        If (-not $?) {
            Write-Error "`>$System`:$Arch`> 可执行程序编译失败"
            # 回到脚本所在目录
            Set-Location -Path $ScriptParentPath
            return
        }
    }
    If ($BuildTargetType -eq 1 -or $BuildTargetType -eq 2) {
        # 输出日志
        Write-Debug "`<$System`:$Arch`> 编译命令：[$CompileCommandForDynamicLinkLibrary]"
        # 执行编译命令
        Invoke-Expression "$CompileCommandForDynamicLinkLibrary"
        # 检查是否编译成功
        If (-not $?) {
            Write-Error "`>$System`:$Arch`> 动态链接库编译失败"
            # 回到脚本所在目录
            Set-Location -Path $ScriptParentPath
            return
        }
    }

    ## 回到脚本所在目录
    Set-Location -Path $ScriptParentPath
    return
}


# 可执行文件压缩
Function Compress ([string]$System, [string]$Arch) {
    # 若 UPX 不存在，则跳出该函数
    If (-not $HasUPX) {
        return
    }
    
    ## 构建压缩命令
    # 构建基本命令
    $CompressCommand = "upx"
    # 根据执行模式，拼接命令
    Switch ($Mode) {
        0 {
            ## 发布模式
            # -t 测试压缩文件
            # -q 安静模式
            # --best 最佳压缩
            # --brute 尝试所有可用的压缩方法和过滤器
            # --ultra-brute 尝试更多的压缩变体
            $CompressCommand += " -q -q -q --best" # --ultra-brute
        }
        1 {
            ## 调试模式
            $CompressCommand += " -v"
        }
    }
    # 追加扩展参数
    If ($CompressExtParams.Length -ne 0) {
        $CompressCommand += " " + $CompressExtParams
    }
    [string]$CompressCommandForExecution = $CompressCommand
    [string]$CompressCommandForDynamicLinkLibrary = $CompressCommand
    If ($CompressExtParamsForExecution.Length -ne 0) {
        $CompressCommandForExecution += " " + $CompressExtParamsForExecution
    }
    If ($CompressExtParamsForDynamicLinkLibrary.Length -ne 0) {
        $CompressCommandForDynamicLinkLibrary += " " + $CompressExtParamsForDynamicLinkLibrary
    }
    # 追加目标文件名
    $CompressCommandForExecution += " $BuildDirName/$System-$Arch/$ProgramName"
    $CompressCommandForDynamicLinkLibrary += " $BuildDirName/$System-$Arch/$ProgramName"
    # 若输出相对路径不为空，则补充输出相对路径
    If ($OutputRelativePath -ne "") {
        $CompressCommandForExecution += "/$OutputRelativePath"
        $CompressCommandForDynamicLinkLibrary += "/$OutputRelativePath"
    }
    $CompressCommandForExecution += "/$ProgramName"
    $CompressCommandForDynamicLinkLibrary += "/$ProgramName"

    ## 设置可执行程序扩展名
    $ExectionExtension = ""
    # 若设置了自定义扩展名，则取自定义扩展名
    If ($CustomExtension -ne "") {
        $ExectionExtension = $CustomExtension
    }
    # 若当前正在编译 Windows 程序，则补充可执行程序后缀名
    ElseIf ($System -eq "windows") {
        $ExectionExtension = ".exe"
    }
    ## 可执行程序输出文件名
    $CompressCommandForExecution += $ExectionExtension

    ## 设置动态链接库扩展名
    $DynamicLinkLibraryExtension = ""
    # 若当前正在编译 Windows 程序，则为 '.dll'
    If ($System -eq "windows") {
        $DynamicLinkLibraryExtension = ".dll"
    }
    # 否则为 '.so'
    Else {
        $DynamicLinkLibraryExtension = ".so"
    }
    ## 动态链接库输出文件名
    $CompressCommandForDynamicLinkLibrary += $DynamicLinkLibraryExtension

    ## 执行压缩
    If ($BuildTargetType -eq 0 -or $BuildTargetType -eq 2) {
        # 输出日志
        Write-Debug "`<$System`:$Arch`> 可执行程序压缩命令：[$CompressCommandForExecution]"
        # 执行 UPX 压缩
        Invoke-Expression "$CompressCommandForExecution"
        # 检查是否压缩成功
        If (-not $?) {
            Write-Error "`<$System`:$Arch`> 可执行程序压缩失败"
            return
        }
    }
    If ($BuildTargetType -eq 1 -or $BuildTargetType -eq 2) {
        # 输出日志
        Write-Debug "`<$System`:$Arch`> 动态链接库压缩命令：[$CompressCommandForDynamicLinkLibrary]"
        # 执行 UPX 压缩
        Invoke-Expression "$CompressCommandForDynamicLinkLibrary"
        # 检查是否压缩成功
        If (-not $?) {
            Write-Error "`<$System`:$Arch`> 动态链接库压缩失败"
            return
        }
    }
    return
}


# 打包
#   输出文件示例：
#   program-name_v1.0.0-alpha_Windows-x64.zip
#   program-name_v1.0.0-alpha_Windows-x32.zip
#   program-name_v1.0.0-alpha_Windows-Arm.zip
#   program-name_v1.0.0-alpha_Windows-Arm64.zip
#   program-name_v1.0.0-alpha_Linux-x32.tar.gz
#   program-name_v1.0.0-alpha_Linux-x64.tar.gz
#   program-name_v1.0.0-alpha_Linux-Arm.tar.gz
#   program-name_v1.0.0-alpha_Linux-Arm64.tar.gz
#   program-name_v1.0.0-alpha_MacOS-x32.tar.gz
#   program-name_v1.0.0-alpha_MacOS-x64.tar.gz
Function PackageFiles ([string]$System, [string]$Arch) {
    # 格式化系统标识及架构标识
    $FormattedSystem = $FormatNames[$System]
    $FormattedArch = $FormatNames[$Arch]
    # 编译输出路径
    $BuildOutputPath = "$BuildDirName/$System-$Arch/$ProgramName"
    # 包名称
    $PackageName = "$ProgramName`_$Version`_$FormattedSystem-$FormattedArch"
    # 若目标系统是 Windows，则输出 .zip 文件，否则输出 .tar.gz 文件
    If ($System -eq "windows") {
        $PackageName += ".zip"
    }
    Else {
        $PackageName += ".tar.gz"
    }
    ## 打包输出路径
    $DistOutputPath = "$ScriptParentPath/$DistDirName/$PackageName"
    
    # 写出程序版本说明文件
    If ($Version.Length -ne 0) {
        Write-Output "$ProgramName($Version) For $FormattedSystem $FormattedArch [$System/$Arch]" > "$BuildOutputPath/version.txt"
    }
    # 复制其他文件
    Foreach ($SrcFilepath in $OutputFiles.Keys) {
        $DestFilepath = $OutputFiles[$SrcFilepath]
        Copy-Item -Force -Recurse -Path $SrcFilepath -Destination "$BuildOutputPath/$DestFilepath"
    }
    # 压缩
    If ($System -eq "windows") {
        Compress-Archive -Path $BuildOutputPath -DestinationPath $DistOutputPath
    }
    Else {
        # 进入到目标构建目录
        Set-Location -Path "$BuildDirName/$System-$Arch"
        # 使用 tar 进行压缩
        tar -czf $DistOutputPath $ProgramName
        # 返回脚本所在目录
        Set-Location -Path $ScriptParentPath
    }
}


# 单架构处理
Function SingleArchitectureProcessing ([string]$System, [string]$Arch) {
    # 格式化系统标识及架构标识
    $FormattedSystem = $FormatNames[$System]
    $FormattedArch = $FormatNames[$Arch]
    # 包名称
    $PackageName = "$ProgramName`_$Version`_$FormattedSystem-$FormattedArch"
    # 若目标系统是 Windows，则输出 .zip 文件，否则输出 .tar.gz 文件
    If ($System -eq "windows") {
        $PackageName += ".zip"
    }
    Else {
        $PackageName += ".tar.gz"
    }
    ## 打包输出路径
    $DistOutputPath = "$DistDirName/$PackageName"

    # 检查是否存在上次打包的输出
    ## 开启了【继续上次构建】选项，且处于发布模式或开启了强制打包，且存在上次打包的输出
    If ($ContinueLastBuild -and ($Publish -or $ForcePackage) -and (Test-Path -Path $DistOutputPath)) {
        # 若存在，则跳过本次构建
        Write-Warning -Message "目标系统架构 `<$System`:$Arch`> 的程序包已存在，跳过本次构建"
        return
    }
    # 检查是否存在上次编译的输出
    ## 未开启【继续上次构建】选项，或不存在上次编译的输出
    If (-not ($ContinueLastBuild -and (Test-Path -Path "$BuildDirName/$System-$Arch/$ProgramName"))) {
        # 编译
        Compile -System $System -Arch $Arch
        If (-not $?) {
            return
        }
    }
    Else {
        # 跳过本次编译
        Write-Warning -Message "目标系统架构 `<$System`:$Arch`> 的编译结果已存在，跳过本次编译"
    }
    # 压缩
    If ($Mode -eq 0 -or $ForceCompress) {
        Compress -System $System -Arch $Arch
        If (-not $?) {
            return
        }
    }
    # 打包
    If ($Mode -eq 0 -or $ForcePackage) {
        PackageFiles -System $System -Arch $Arch
        If (-not $?) {
            return
        }
    }
    return
}


# 多架构处理
Function MultiArchitectureProcessing ([string]$SpecifiedSystem="") {
    # 遍历跨平台支持列表
    Foreach ($System in $SupportList.Keys) {
        # 若指定的操作系统不为空，且当前遍历的系统不是指定的系统，则跳过
        If ($SpecifiedSystem -ne "" -and $SpecifiedSystem -ne $System) {
            Continue
        }
        # 若允许构建的系统集合不为空，且当前遍历的操作系统不在允许构建的系统集合中，则跳过
        If ($AllowSystems.Length -ne 0 -and -not $AllowSystems.Contains($System)) {
            Continue
        }
        ## 遍历架构类型
        Foreach ($Arch in $SupportList[$System]) {
            # 若允许构建的架构类型集合不为空，且当前遍历的架构类型不在允许构建的架构类型集合中，则跳过
            If ($AllowArches.Length -ne 0 -and -not $AllowArches.Contains($Arch)) {
                Continue
            }
            ## 执行处理
            # $item[0]: 目标系统
            # $item[1]: 目标架构
            Write-Output "  当前正在编译 `<$System`:$Arch`> 版本..."
            SingleArchitectureProcessing -System $System -Arch $Arch
            If (-not $?) {
                # 若某系统架构编译失败，则跳过
                Continue
            }
        }
    }
    # 返回成功
    return
}

# 处理
Function Processing () {
    # 若启用了跨平台编译，则编译所有平台版本
    If ($CrossPlatform) {
        Write-Output "开始编译全平台版本..."
        MultiArchitectureProcessing
        return
    }
    # 若指定了目标系统，则：
    If ($TargetSystem -ne "") {
        # 格式化系统名称
        $TargetSystem = $SystemNameMapping[$TargetSystem]
        # 判断是否指定了目标架构，
        # 若是，则仅编译指定架构版本；
        # 否则，编译指定系统下的所有架构版本。
        If ($TargetArch -ne "") {
            # 格式化架构名称
            $TargetArch = $ArchNameMapping[$TargetArch]
            # 仅编译指定的系统架构版本
            Write-Output "开始编译 `<$TargetSystem`:$TargetArch`> 版本..."
            SingleArchitectureProcessing -System $TargetSystem -Arch $TargetArch
            return
        }
        Else {
            # 编译指定系统下的所有架构版本
            Write-Output "开始编译 $TargetSystem 系统全架构版本..."
            MultiArchitectureProcessing -System $TargetSystem
            return
        }
    }
    # 编译当前系统版本
    Write-Output "开始编译当前系统架构版本..."
    SingleArchitectureProcessing -System $(go env GOOS) -Arch $(go env GOARCH)
    return
}

# 主函数
Function Main {
    # 检查参数
    CheckParameters
    # 执行前置准备
    Prepare
    # 执行处理任务
    Processing
    # 清除构建时产生的文件及目录
    If ($Publish -and (-not $Unclear) -and (Test-Path "$ScriptParentPath/$BuildDirName")) {
        Remove-Item -Force -Recurse -Path "$ScriptParentPath/$BuildDirName"
    }
    Exit 0
}



<# 执行主函数 #>
Main
