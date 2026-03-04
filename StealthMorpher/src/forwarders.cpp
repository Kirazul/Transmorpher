extern "C" void* p[5];

// All forwarders MUST be __declspec(naked) to prevent MSVC from generating
// push ebp/mov ebp,esp prologue which would corrupt the calling convention.
extern "C" {
    __declspec(naked) void dinput8_DirectInput8Create() { __asm { jmp p[0*4] } }
    __declspec(naked) void dinput8_GetdfDIJoystick()    { __asm { jmp p[1*4] } }
    __declspec(naked) void dinput8_GetdfDIKeyboard()    { __asm { jmp p[2*4] } }
    __declspec(naked) void dinput8_GetdfDIMouse()       { __asm { jmp p[3*4] } }
    __declspec(naked) void dinput8_GetdfDIMouse2()      { __asm { jmp p[4*4] } }
}
