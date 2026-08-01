#!/usr/bin/env pwsh
# Vidya — Lexing and Parsing in PowerShell
#
# A tokenizer is byte-by-byte classification: read one character,
# decide what it is, branch to a handler. Parsing wraps that loop
# and asks "what shape is this?". PowerShell's pipeline lets us
# express both elegantly: each cmdlet emits objects and the next
# stage classifies them.

<#
Block comments span multiple lines. Useful for command-help
metadata blocks at the top of advanced functions.

  .SYNOPSIS
    A toy lexer that classifies bytes.
  .DESCRIPTION
    Walks one character at a time, builds tokens.
#>


function Get-TokenKind {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Byte
    )

    if ($Byte -match '\d') {
        return 'digit'
    } elseif ($Byte -match '[A-Za-z_]') {
        return 'letter'
    } elseif ($Byte -match '\s') {
        return 'whitespace'
    } else {
        return 'punct'
    }
}


function Read-Number {
    param([string]$Source, [int]$Start)

    $i = $Start
    $value = 0
    while ($i -lt $Source.Length -and (Get-TokenKind -Byte $Source[$i]) -eq 'digit') {
        $digit = [int]$Source[$i] - [int]'0'
        $value = $value * 10 + $digit
        $i = $i + 1
    }
    return @{
        Kind  = 'number'
        Start = $Start
        End   = $i
        Value = $value
    }
}


function Tokenize {
    param([string]$Source)

    $tokens = @()
    $pos = 0
    while ($pos -lt $Source.Length) {
        $kind = Get-TokenKind -Byte $Source[$pos]
        if ($kind -eq 'digit') {
            $token = Read-Number -Source $Source -Start $pos
            $tokens += $token
            $pos = $token.End
        } elseif ($kind -eq 'whitespace') {
            $pos = $pos + 1
        } else {
            $tokens += @{ Kind = $kind; Start = $pos; End = $pos + 1 }
            $pos = $pos + 1
        }
    }
    return $tokens
}


# Drive it. The pipe chains stages, each ingesting the previous
# stage's output. Get-Process / Where-Object / Select-Object
# is the canonical sysadmin one-two; here we keep it pure.
$src = "42 abc 7 q"
$result = Tokenize -Source $src
$result | ForEach-Object {
    "$($_.Kind) [$($_.Start)..$($_.End)]"
}


# Type literals + scope-prefixed variables are common in
# advanced scripts. `[hashtable]` is the type; `$global:CACHE`
# and `$env:PATH` show scope qualification.
[hashtable]$config = @{
    'mode'    = 'lex'
    'verbose' = $true
    'depth'   = 3
}
$global:CACHE = $config
"PATH = $($env:PATH)"


# Try/catch with throw — error handling shape that maps onto
# the PowerShell exception model.
try {
    if ($config.depth -gt 10) {
        throw "depth too large: $($config.depth)"
    }
    Write-Host "ok"
} catch {
    Write-Host "error: $_"
} finally {
    Write-Host "done"
}

# 2.3.2 error-hole coverage: `\` is the Windows path separator
# and appears unquoted in bare-word arguments constantly.
Set-Location C:\Users\vyakarana\corpus
& .\scripts\smoke.ps1 -Path C:\build\vyk.exe
