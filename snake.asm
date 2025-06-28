.model flat,stdcall
option casemap:none

extern ExitProcess@4:proc
extern GetStdHandle@4:proc
extern MessageBoxA@16:proc
extern WriteConsoleA@20:proc
extern Sleep@4:proc
extern GetAsyncKeyState@4:proc

MAP_WIDTH   equ 20
MAP_HEIGHT  equ 20
MAP_SIZE    equ 400
ITEM_NULL   equ 0;地上什么都没有
ITEM_WALL   equ 1;这里有墙。你也可以拆掉墙，或者自定义墙。
ITEM_BODY   equ 2;这是蛇的身体
ITEM_FOOD   equ 3;这是一般的食物
TOW_UP      equ 0
TOW_RIGHT   equ 1
TOW_DOWN    equ 2
TOW_LEFT    equ 3;上下左右


FRAME_DELAY_MS equ 120

.data
map         db MAP_SIZE dup(0);地图大小为20*20，或许你可以调整一下
snake       dw MAP_SIZE dup(0);维护蛇的身体状态。这两个字节分别存放该节身体的坐标。
snake_head  dw 0
snake_tail  dw 0
snake_len   dw 0
snake_tow   db 0
rand_seed   dd 12345678h


szBuffer    db MAP_WIDTH dup(0),13,10,0
szFinished  db "Snake Died",0

outch       db ' ','#','*','.'
control     dw -MAP_WIDTH, 1, MAP_WIDTH, -1
handle      dd 0
temp        dd 0

default_map db MAP_WIDTH dup(1)
            db 18 dup(1,18 dup(0),1)
            db MAP_WIDTH    dup(1)
ANSI_CLEAR db 27,'[','2','J',27,'[','H',0

.code

rand proc;基于LCG
    mov eax, [offset rand_seed]
    imul eax,eax, 1103515245;
    add eax,12345
    mov rand_seed, eax
    ret
rand endp

spawn_food proc
try_spawn_food:
    call rand;先整个随机数
    mov ebx,offset map
    mov ecx,MAP_SIZE
    xor edx,edx
    div ecx;看看随机到哪里了
    mov esi,edx
    mov cl,[ebx+esi]
    cmp cl,ITEM_NULL
    jne try_spawn_food;如果随机到了非空地上就重来
    mov cl,ITEM_FOOD
    mov [ebx+esi],cl;设置食物位置
    ret
spawn_food endp

clear_screen proc
    ;push 0
    ;push offset temp
    ;push 8
    ;push offset ANSI_CLEAR
    ;mov eax,[offset handle]
    ;call WriteConsoleA@20
    ret;我没有清屏，反正又不是不能玩
clear_screen endp

display proc;现在只能输出地图，或许你还能输出点别的什么东西？
	call clear_screen
    mov ecx,MAP_HEIGHT
    mov ebx,offset map;
    mov ebp,offset outch;
output_each_line:    
    mov edx,MAP_WIDTH
    mov edi,offset szBuffer
output_each_char:
    xor eax,eax
    mov al,[ebx]
    inc ebx
    mov esi,eax
    mov al,[ebp+esi]
    mov [edi],al
    inc edi
    dec edx
    cmp edx,0
    jne output_each_char
    mov eax,[offset handle]
    push ecx
    push ebx
    push ebp
    push 0
    push offset temp
    push MAP_WIDTH+2
    push offset szBuffer
    push eax
    call WriteConsoleA@20
    pop ebp
    pop ebx
    pop ecx
    dec ecx
    cmp ecx,0
    jne output_each_line
    ret
display endp

init proc
    push -11
    call GetStdHandle@4
    mov [offset handle],eax
    
    mov edi,offset map;把地图从default map复制到map。你可以通过修改default map来修改关卡
    mov esi,offset default_map
    mov ecx,100;为什么dw的时候400，这里就是200呢
fake_memcpy:
    mov eax,[esi];或许你也可以试着用sse初始化内存？如果在16位环境中要怎么修改呢？
    mov [edi],eax
    add esi,4
    add edi,4
    dec ecx
    cmp ecx,0
    jne fake_memcpy
    mov ebx,offset snake
    mov ax,210;蛇的初始位置是10，10.你也可以修改。分别通过al、ah传入也是可以的
    mov [ebx],ax
    mov byte ptr[offset map+210],2
    call spawn_food
    call display
    ret
init endp

sleep proc
    mov ecx, FRAME_DELAY_MS
    push ecx
    call Sleep@4
    ret
sleep endp

move_and_judge proc
    xor esi,esi
    xor ecx,ecx
    xor eax,eax
    mov cl,[offset snake_tow];获取当前蛇朝向
    mov edi,ecx
    mov ebx,offset snake;获取当前蛇状态
    mov si,[offset snake_head]
    shl esi,1
    mov ax,[ebx+esi];snake[snake_head]
    mov ebp,offset control;将分支判断转化为访存以提升性能，一个很常见的优化方式
    shl edi,1
    mov cx,[ebp+edi]
    add ax,cx;检查目标块
    mov esi,eax
    mov ebp,offset map
    mov al,[ebp+esi];如果你想把四周的围墙拆掉，这里要进行大改。为什么呢？
    cmp al,ITEM_NULL
    je clear_tail
    cmp al,ITEM_FOOD
    jne failed
    pushad
    call spawn_food
    popad
    jmp move_head
clear_tail:
    mov ax,[offset snake_tail]
    mov edi,eax
    inc ax
    xor dx,dx
    mov cx,MAP_SIZE
    div cx
    mov [offset snake_tail],dx;snake_tail=(snake_tail+1)%MAP_SIZE
    shl edi,1
    mov di,[ebx+edi];获取上一个tail的位置
    mov byte ptr[ebp+edi],ITEM_NULL;map[snake_tail]=ITEM_NULL
move_head:    
    mov ax,[offset snake_head]
    inc ax
    xor edx,edx
    mov cx,MAP_SIZE
    div cx
    mov [offset snake_head],dx;snake_head=(snake_head+1)%MAP_SIZE
    mov edi,edx
    shl edi,1
    mov [ebx+edi],si
    mov byte ptr[ebp+esi],ITEM_BODY;map[next_vis]=ITEM_BODY
    xor eax,eax
    ret
failed:
    mov eax,1
    ret
move_and_judge endp

get_input proc;这个监听输入的函数有可能会遗漏用户输入，你注意到了吗？
    push 'W'
    call GetAsyncKeyState@4
    test eax, 8000h
    jz judge_s
    mov byte ptr[offset snake_tow], TOW_UP
judge_s:
    push 'S'
    call GetAsyncKeyState@4
    test eax, 8000h
    jz judge_a
    mov byte ptr[offset snake_tow], TOW_DOWN
judge_a:
    push 'A'
    call GetAsyncKeyState@4
    test eax, 8000h
    jz judge_d
    mov byte ptr[offset snake_tow], TOW_LEFT
judge_d:
    push 'D'
    call GetAsyncKeyState@4 
    test eax, 8000h
    jz finish
    mov byte ptr[offset snake_tow], TOW_RIGHT
finish:
    ret
get_input endp


main_loop proc
run:
    call get_input
    call move_and_judge
    cmp eax,0
    jne finish
    call display
    call sleep
    jmp run
finish:
    ret
main_loop endp

start proc
    call init ;调用初始化逻辑
    call main_loop
    mov edx,offset szFinished
    push 0
    push edx
    push edx
    push 0
    call MessageBoxA@16
    push 0
    call ExitProcess@4
start endp
end start
