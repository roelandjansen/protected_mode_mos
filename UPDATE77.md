# UPDATE 77 -- hook check: plain vectors skip the special cases (2026-10-07)

Files: `_386.ASM` only, on top of UPDATE 76. Delivered together with
UPDATE 78 in `u78/_386.ASM`.

## Why

After UPDATE 75/76 the hook check (`einvhook` .. `einvh1`) still cost
47 monitor instructions per int 31h. `einvhook` tests one by one for
the stub re-entries (E6h, E9h, EAh, E7h, E8h) and then goes through
`einxcpt`, which only acts on vectors 0-7. Every other vector -- int
31h, int 21h, IRQs -- walks all of those tests and still ends at
`einvh1`.

## Change

At the top of `einvhook`:

```
	cmp	dl,08h
	jb	einvhk0		; 0-7: exceptions, the full chain
	cmp	dl,0e6h
	jae	einvhk0		; E6h-FFh: stub re-entries, the full chain
	jmp	einvh1		; 08h-E5h: straight to the hook lookup
einvhk0:			; the old chain, unchanged
```

For 08h-E5h the old chain always reached `einvh1` with the same
registers (dl = vector, ebx = nca; `einxcpt`'s `einx1` path goes to
`einxno` -> `einvh1` for anything above 7). Vectors 0-7 and E6h-FFh
take the old path unchanged.

## Encoding checked in the linked binary

| offset | bytes | meaning |
| --- | --- | --- |
| 5692 | `80 FA 08 72 09` | cmp dl,8 / jb 56A0 (old chain) |
| 5697 | `80 FA E6 73 04` | cmp dl,0E6h / jae 56A0 |
| 569C | `66 E9 F0 00` | jmp einvh1 (5790) |

## Measurement (gdb-gated hook, `hookprof.sh`, Q300)

| | 74 | 75 | 76 | 77 |
| --- | --- | --- | --- | --- |
| 0300h call, monitor instructions | 479 | 440 | 423 | **401** |
| hook check | 70 | 47 | 47 | 32 |

Three clean calls: 402 / 400 / 401. Since UPDATE 74: -78 per 0300h
call (-16 %); every int 31h call and every reflected interrupt in
08h-E5h saves ~15.

## Tests

Run on the UPDATE 78 build (77 + 78); see UPDATE78.md.
