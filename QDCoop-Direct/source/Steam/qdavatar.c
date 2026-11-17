/* FSteamID has no reflected fields: Lua serializes it as an empty table.
 * Keep its uint64 intact and call the original SteamBridge/UMG functions.
 * Game-thread only, validated reflected layouts; no transport or asset logic. */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdint.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>
typedef struct {const char *data;size_t size;} View;
static void*(*construct)(void*,void*);static void(*destruct)(void*);
static View*(*getstring)(void*,View*,int);static void(*setstring)(void*,const char*,size_t);static bool(*isstring)(void*,int);
static void(*event)(void*,void*,void*);static int*(*offset)(void*);static int*(*size)(void*);static uint16_t*(*parms)(void*);static bool(*isa)(void*,void*);
static void *avatar,*friendsClass,*brush,*imageClass,*textureClass;static int bound,ready;
static int bind(void){if(bound)return 1;HMODULE h=GetModuleHandleW(L"UE4SS.dll");if(!h)return 0;
#define API(v,n) {FARPROC p=GetProcAddress(h,n);memcpy(&v,&p,sizeof(p));if(!v)return 0;}
 API(construct,"??0Lua@LuaMadeSimple@RC@@QEAA@PEAUlua_State@@@Z");API(destruct,"??1Lua@LuaMadeSimple@RC@@QEAA@XZ");
 API(getstring,"?get_string@Lua@LuaMadeSimple@RC@@QEBA?AV?$basic_string_view@DU?$char_traits@D@std@@@std@@H@Z");API(setstring,"?set_string@Lua@LuaMadeSimple@RC@@QEBAXPEBD_K@Z");API(isstring,"?is_string@Lua@LuaMadeSimple@RC@@QEBA_NH@Z");
 API(event,"?ProcessEvent@UObject@Unreal@RC@@QEAAXPEAVUFunction@23@PEAX@Z");API(offset,"?GetOffset_Internal@FProperty@Unreal@RC@@QEAAAEAHXZ");API(size,"?GetElementSize@FProperty@Unreal@RC@@QEAAAEAHXZ");API(parms,"?GetParmsSize@UFunction@Unreal@RC@@QEAAAEAGXZ");API(isa,"?IsA@UObjectBase@Unreal@RC@@QEBA_NPEAVUClass@23@@Z");bound=1;return 1;
}
static int number(char**p,uint64_t*v){while(**p==' ')(*p)++;char*e;*v=strtoull(*p,&e,10);if(e==*p)return 0;*p=e;return 1;}
__declspec(dllexport) int qdavatar(void*L){if(!bind())return 0;
 __attribute__((aligned(16))) unsigned char lua[512]={0};construct(lua,L);const char*result="0";View v={0};
 if(!isstring(lua,1))goto done;
 getstring(lua,&v,1);if(!v.data||v.size<2||v.size>=1024)goto done;
 char command[1024];memcpy(command,v.data,v.size);command[v.size]=0;char*p=command+1;
 if(command[0]=='I'){
  ready=0;uint64_t a[11];for(int i=0;i<11;i++)if(!number(&p,&a[i])||!a[i])goto done;if(*p)goto done;
  int offsets[]={0,8,12,16,0,8},sizes[]={8,1,4,8,8,1};
  for(int i=0;i<6;i++)if(*offset((void*)(uintptr_t)a[i+5])!=offsets[i]||*size((void*)(uintptr_t)a[i+5])!=sizes[i])goto done;
  avatar=(void*)(uintptr_t)a[0];friendsClass=(void*)(uintptr_t)a[1];brush=(void*)(uintptr_t)a[2];imageClass=(void*)(uintptr_t)a[3];textureClass=(void*)(uintptr_t)a[4];
  if(*parms(avatar)!=24||*parms(brush)<9||*parms(brush)>32)goto done;
  ready=1;result="1";
 }else if(command[0]=='A'&&ready){
  uint64_t a[4];for(int i=0;i<4;i++)if(!number(&p,&a[i]))goto done;if(*p||!a[0]||!a[1]||!a[2]||!a[3]||a[3]>INT32_MAX)goto done;
  void*f=(void*)(uintptr_t)a[1],*image=(void*)(uintptr_t)a[2];if(!isa(f,friendsClass)||!isa(image,imageClass))goto done;
  struct {uint64_t id;uint8_t kind,pad[3];int32_t handle;void*texture;} args={a[0],0,{0},0,NULL};
  event(f,avatar,&args);if(args.handle!=(int32_t)a[3]||!args.texture||!isa(args.texture,textureClass))goto done;
  __attribute__((aligned(16))) unsigned char b[32]={0};memcpy(b,&args.texture,8);event(image,brush,b);result="1";
 }
 done:setstring(lua,result,strlen(result));destruct(lua);return 1;
}

