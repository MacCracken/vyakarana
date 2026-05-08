; vyakarana stand-in -- not from vidya. See docs/adr/0006-standin-corpus-policy.md.
; Re-sync when vidya adds an LLVM-IR reference sample.
;
; Demonstrates LLVM-IR (textual): module metadata, type
; declarations, named globals, function definitions with
; attributes, basic-block labels, common instructions
; (alloca/load/store/getelementptr/call/ret/br/icmp/phi),
; and !metadata references.

; ── Module-level metadata ──────────────────────────────────────────

target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-f80:128-n8:16:32:64-S128"
target triple    = "x86_64-unknown-linux-gnu"

source_filename  = "concept.cyr"

; ── Named struct types ────────────────────────────────────────────

%struct.Token = type { i8, i32, i32 }
%struct.Tokenbuf = type { ptr, i64, i64 }

; ── Globals ───────────────────────────────────────────────────────

@.str.empty   = private unnamed_addr constant [1 x i8] c"\00", align 1
@.str.hello   = private unnamed_addr constant [6 x i8] c"hello\00", align 1
@version_str  = dso_local local_unnamed_addr global [13 x i8] c"vyk 1.9.0\0A\00\00\00", align 1
@global_count = internal global i64 0, align 8

; External declaration.
declare i32 @printf(ptr noundef, ...) #0

; ── Function: zero-init a tokenbuf ────────────────────────────────

define dso_local noundef ptr @tokenbuf_new() local_unnamed_addr #1 {
entry:
    %call = tail call noalias ptr @malloc(i64 noundef 24) #2
    %cast = bitcast ptr %call to ptr
    store ptr null,    ptr %cast,                   align 8
    %len_ptr = getelementptr inbounds %struct.Tokenbuf, ptr %cast, i32 0, i32 1
    store i64 0,       ptr %len_ptr,                align 8
    %cap_ptr = getelementptr inbounds %struct.Tokenbuf, ptr %cast, i32 0, i32 2
    store i64 0,       ptr %cap_ptr,                align 8
    ret ptr %cast
}

declare noalias ptr @malloc(i64 noundef) local_unnamed_addr #2

; ── Function: append a token ──────────────────────────────────────
; fn tokenbuf_push(tb: *Tokenbuf, kind: i8, start: i32, len: i32)

define dso_local void @tokenbuf_push(ptr noundef %tb,
                                     i8  noundef %kind,
                                     i32 noundef %start,
                                     i32 noundef %len) local_unnamed_addr #1 {
entry:
    %len_ptr = getelementptr inbounds %struct.Tokenbuf, ptr %tb, i32 0, i32 1
    %len_now = load i64, ptr %len_ptr, align 8
    %cap_ptr = getelementptr inbounds %struct.Tokenbuf, ptr %tb, i32 0, i32 2
    %cap     = load i64, ptr %cap_ptr, align 8
    %need_grow = icmp uge i64 %len_now, %cap
    br i1 %need_grow, label %grow, label %store

grow:
    %new_cap_2x = shl i64 %cap, 1
    %is_zero    = icmp eq i64 %cap, 0
    %new_cap    = select i1 %is_zero, i64 16, i64 %new_cap_2x
    %data_ptr   = getelementptr inbounds %struct.Tokenbuf, ptr %tb, i32 0, i32 0
    %old_data   = load ptr, ptr %data_ptr, align 8
    %elem_size  = mul i64 %new_cap, 12
    %new_data   = call ptr @realloc(ptr noundef %old_data, i64 noundef %elem_size) #2
    store ptr %new_data, ptr %data_ptr, align 8
    store i64 %new_cap,  ptr %cap_ptr,  align 8
    br label %store

store:
    %data_ptr2 = getelementptr inbounds %struct.Tokenbuf, ptr %tb, i32 0, i32 0
    %data2     = load ptr, ptr %data_ptr2, align 8
    %slot_off  = mul i64 %len_now, 12
    %slot      = getelementptr inbounds i8, ptr %data2, i64 %slot_off
    store i8  %kind,  ptr %slot, align 1
    %s_off     = getelementptr inbounds i8, ptr %slot, i64 4
    store i32 %start, ptr %s_off, align 4
    %l_off     = getelementptr inbounds i8, ptr %slot, i64 8
    store i32 %len,   ptr %l_off, align 4
    %len_next  = add i64 %len_now, 1
    store i64 %len_next, ptr %len_ptr, align 8
    ret void
}

declare ptr @realloc(ptr noundef, i64 noundef) local_unnamed_addr #2

; ── Function: greet (calls printf) ────────────────────────────────

define dso_local i32 @greet(ptr noundef %name) local_unnamed_addr #1 {
entry:
    %fmt = getelementptr inbounds [13 x i8], ptr @version_str, i64 0, i64 0
    %ret = tail call i32 (ptr, ...) @printf(ptr noundef %fmt) #2
    ret i32 0
}

; ── Function attributes ───────────────────────────────────────────

attributes #0 = { nounwind willreturn allocsize(0) }
attributes #1 = { nounwind uwtable "frame-pointer"="all" }
attributes #2 = { nounwind allocsize(0) "no-builtins" }

; ── Module-level metadata ─────────────────────────────────────────

!llvm.module.flags = !{!0, !1, !2}
!llvm.ident        = !{!3}

!0 = !{i32 1, !"wchar_size", i32 4}
!1 = !{i32 7, !"PIC Level", i32 2}
!2 = !{i32 7, !"uwtable", i32 2}
!3 = !{!"vyakarana stand-in 1.9.0"}
