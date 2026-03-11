# Product Requirements Document: ding

**Author**: sijun
**Date**: 2026-03-11
**Status**: Draft (Post-PoC)
**Previous**: [prd-watchtask.md](./prd-watchtask.md) (Pre-PoC, 2026-03-10)

---

## 1. Executive Summary

**ding**은 Mac에서 실행되는 장시간 작업(빌드, 테스트, 배포, LLM 에이전트 등)의 완료·실패 이벤트를 iPhone/Apple Watch 알림으로 전달하는 CLI 도구다.

개발자는 `ding wait -- npm run build` 한 줄로, 명령이 끝나면 iPhone 알림과 손목의 Apple Watch 진동으로 결과를 확인할 수 있다. Mac을 떠나 커피를 마시거나, 다른 작업을 하더라도 결과를 놓치지 않는다.

5일간의 기술 스파이크(PoC)를 통해, 원래 구상했던 3-hop 로컬 네트워크 아키텍처 대신 **APNs visible push + iOS 알림 미러링**이라는 극적으로 단순한 아키텍처를 발견하고 검증했다. CLI 1개와 Cloudflare Workers 릴레이 1개로 전체 시스템이 동작하며, Mac 앱·WatchConnectivity·Bonjour/TCP가 모두 불필요하다.

---

## 2. Background & Context

### 문제 공간

Mac에서 실행 중인 터미널 명령의 완료를 모바일에서 알 수 있는 방법이 없다. macOS 알림 배너는 Mac 앞에 있어야만 보이고, iPhone이나 Apple Watch로는 전달되지 않는다.

개발자의 일상에는 "기다림"이 빈번하다:
- 코드 빌드/컴파일 (수십 초 ~ 수십 분)
- 테스트 스위트 실행 (수 분 ~ 수십 분)
- LLM 에이전트 작업 완료 대기 (가변)
- CI/CD 파이프라인 (수 분 ~ 수십 분)
- Docker 이미지 빌드, ML 모델 학습

현재 대처 방식: Mac 앞에 앉아서 기다리거나, 주기적으로 확인하러 돌아오거나, macOS 알림 배너에 의존. Mac을 떠나면 이 알림을 놓친다.

### PoC 결과 요약 (5일 스파이크)

원래 PRD에서 계획했던 아키텍처:
```
CLI → Mac 앱 (IPC) → Bonjour/TCP → iPhone → WatchConnectivity → Watch
                   └→ APNs 릴레이 (폴백)
```

PoC에서 발견한 문제:
1. **Silent push는 신뢰할 수 없다** — iPhone이 5분 이상 백그라운드에 있으면 배달률이 급격히 하락
2. **로컬 TCP 경로의 체감 이점이 없다** — APNs 대비 ~500ms 빠르지만 사용자가 구분 불가
3. **Mac 앱이 불필요한 복잡성을 추가한다** — CLI가 직접 HTTP를 보내면 IPC, Mac 앱 데몬이 불필요
4. **WatchConnectivity가 불필요하다** — iOS visible push는 자동으로 Watch에 미러링됨

**검증된 최종 아키텍처:**
```
CLI (ding) → HTTP POST → Cloudflare Workers → APNs visible push → iPhone → Watch (자동 미러링)
```

| 지표 | 목표 | 실제 |
|------|------|------|
| 전달 성공률 | >90% | **100%** (30+ 회 테스트) |
| E2E 레이턴시 P50 | <5초 | **1-2초** |
| 10개 연속 전송 | 누락 없음 | **10/10** (JWT 캐싱 후) |
| Exit code 보존 | 동작 | **동작** (0, 1 테스트) |

### 시장 현황

- **직접 경쟁자 없음**: Mac CLI → iPhone/Watch 푸시 알림 도구가 App Store에 존재하지 않음
- **간접 대안**: Pushover (서버 경유, 개발자 UX 아님), ntfy (자체 호스팅 필요, Watch 지원 미비)
- **기회**: Apple 생태계 개발자 중 Mac + Watch 동시 사용자가 증가하는 추세에서 명확한 공백

---

## 3. Objectives & Success Metrics

### Goals

1. CLI 한 줄(`ding wait -- <command>`)로 명령 완료 시 iPhone/Apple Watch에 1-3초 내 알림 전달
2. 설치 후 첫 알림까지 3분 이내 완료 가능한 개발자 경험
3. 서버 운영 비용 실질적 제로 (Cloudflare Workers 무료 티어: 100K req/day)
4. 솔로 개발자가 4주 이내에 MVP 출시 가능한 기술적 단순함

### Non-Goals

1. **Watch → Mac 리모트 컨트롤**: 양방향 통신은 v1 범위 밖. 알림 수신(단방향)에 집중
2. **커스텀 Watch UI/햅틱**: v1은 iOS 시스템 알림 미러링 사용. Watch 전용 앱 UI와 커스텀 햅틱 패턴은 v2 고려
3. **로컬 전용 모드**: PoC 결과, APNs 릴레이 경유가 가장 안정적. 인터넷 연결 필수
4. **비개발자 타겟**: v1은 터미널 사용자에 집중. GUI-only 경험은 v2 이후
5. **Mac 앱 / 메뉴바 UI**: PoC에서 불필요함이 확인됨. CLI만으로 충분
6. **플러그인/훅 시스템**: v1은 CLI 핵심 기능에 집중. 확장 시스템은 v2

### Success Metrics

| Metric | Current | Target | Measurement |
|--------|---------|--------|-------------|
| 알림 전달 성공률 | N/A | >99% | 릴레이 서버 로그 (APNs 응답 코드) |
| E2E 레이턴시 P50 | N/A | <3초 | CLI 전송 시각 → APNs 응답 시각 기록 |
| CLI 설치 → 첫 알림 소요 시간 | N/A | <3분 | 온보딩 가이드 기준 |
| 주간 활성 사용률 (WAU/Install) | N/A | >40% (베타 4주차) | 릴레이 서버 고유 토큰별 요청 수 |
| 일 평균 알림 전송 횟수 | N/A | >3회/일 (활성 사용자) | 릴레이 서버 로그 |

---

## 4. Target Users & Segments

### Primary: 터미널 중심 Mac 개발자

- MacBook + iPhone 사용 (Apple Watch는 선택적 — 있으면 자동 미러링)
- 일일 빌드/테스트를 빈번히 실행 (iOS, 웹, 백엔드 개발자)
- Homebrew, CLI 도구에 익숙
- 빌드 대기 시간에 자리를 비우거나 다른 작업을 하고 싶어함

**규모 추정**: 전 세계 Mac 개발자 ~4.5M명 중, iPhone 사용자 비율 ~90%+ → **~4M 잠재 사용자** (Apple Watch 소유 시 경험 향상, 필수 아님)

### Secondary: AI/ML 엔지니어

- LLM 에이전트, ML 모델 학습 등 장시간 비동기 작업이 잦음
- 작업 완료 타이밍을 예측하기 어려움

### Tertiary: DevOps/SRE

- CI/CD 파이프라인, 배포 작업 모니터링
- 웹훅 기반 통합에 익숙

---

## 5. User Stories & Requirements

### P0 — Must Have (MVP)

| # | User Story | Acceptance Criteria |
|---|-----------|-------------------|
| P0-1 | 개발자로서, `ding wait -- <command>`로 명령을 래핑하면, 완료 시 Apple Watch에 알림을 받고 싶다 | (1) 원래 명령의 stdout/stderr 그대로 출력 (2) exit code 보존 (3) 완료 후 3초 이내 Watch 알림 도착 (4) 알림에 명령 이름, 실행 시간, 성공/실패 표시 |
| P0-2 | 개발자로서, `ding notify "메시지"`로 임의 텍스트를 Watch에 전송하고 싶다 | (1) 문자열을 Watch 알림 본문으로 전달 (2) `--status` 옵션으로 success/failure/warning/info 지정 가능 (3) 셸 스크립트, CI 스크립트 등에서 호출 가능 |
| P0-3 | 개발자로서, `brew install ding`으로 설치하고 3분 내에 첫 알림을 받고 싶다 | (1) Homebrew 원클릭 설치 (2) `ding setup`으로 디바이스 토큰 등록 (3) `ding test`로 테스트 알림 전송 → Watch 도착 확인 |
| P0-4 | 사용자로서, iPhone에 컴패니언 앱을 설치하면, Watch에 별도 설치 없이 알림이 오길 원한다 | (1) iOS 앱이 APNs 토큰 등록 (2) 알림은 iOS 시스템 푸시로 도착 (3) iPhone 잠금/백그라운드 상태에서도 자동으로 Watch에 미러링 |
| P0-5 | 사용자로서, 10개 알림을 빠르게 연속 전송해도 누락 없이 모두 Watch에 도착해야 한다 | (1) 1초 간격 10개 전송 시 100% 전달 (2) APNs JWT rate limit 없음 (서버 사이드 캐싱) |

### P1 — Should Have (v1.1)

| # | User Story | Acceptance Criteria |
|---|-----------|-------------------|
| P1-1 | 개발자로서, 셸 프로필에 자동 훅을 설치하여 30초 이상 걸리는 명령이 완료되면 자동 알림을 받고 싶다 | (1) `ding install-hook`으로 zsh/bash에 훅 추가 (2) 임계값 사용자 설정 가능 (기본 30초) (3) `ding uninstall-hook`으로 제거 |
| P1-2 | 사용자로서, `ding status`로 릴레이 서버 연결 상태를 확인하고 싶다 | (1) 릴레이 서버 health check (2) 등록된 디바이스 토큰 유효성 확인 (3) 최근 전송 이력 표시 |
| P1-3 | 사용자로서, 알림에 앱 아이콘과 커스텀 사운드를 적용하고 싶다 | (1) iOS 앱에 커스텀 알림 사운드 번들 (2) 성공/실패별 다른 사운드 (3) Watch 미러링 시 사운드 반영 |
| P1-4 | 사용자로서, 디바이스 토큰이 변경되면 자동으로 갱신되어야 한다 | (1) iOS 앱이 토큰 변경 감지 (2) 새 토큰을 릴레이 서버에 자동 등록 (3) CLI 재설정 불필요 |
| P1-5 | 사용자로서, 알림 히스토리를 iPhone 앱에서 확인하고 싶다 | (1) 수신된 알림 목록 (제목, 상태, 시간) (2) 최근 50건 저장 (3) 알림 탭 시 상세 보기 |

### P2 — Nice to Have / Future (v2)

| # | User Story | Acceptance Criteria |
|---|-----------|-------------------|
| P2-1 | 사용자로서, Watch에서 커스텀 햅틱(성공=부드러운 탭, 실패=강한 진동)을 구분하고 싶다 | (1) Watch 전용 앱에서 알림 인터셉트 (2) status별 WKHapticType 매핑 (3) Rich notification UI |
| P2-2 | 개발자로서, CI/CD 파이프라인에서 웹훅으로 Watch 알림을 보내고 싶다 | (1) 릴레이 서버에 인증 토큰 기반 웹훅 엔드포인트 (2) GitHub Actions, GitLab CI 등에서 curl로 호출 (3) JSON 페이로드 스펙 문서화 |
| P2-3 | 개발자로서, 특정 파일/디렉토리 변경 시 Watch 알림을 받고 싶다 | (1) `ding watch <path>` 명령 (2) FSEvents 기반 변경 감지 (3) 파일명, 변경 유형 포함 |
| P2-4 | 개발자로서, 특정 프로세스 종료 시 Watch 알림을 받고 싶다 | (1) `ding watch-pid <PID>` (2) 종료 코드 포함 (3) 이미 종료된 경우 즉시 알림 |
| P2-5 | 사용자로서, 여러 Mac에서 동일한 Watch로 알림을 받고 싶다 | (1) 동일 디바이스 토큰을 여러 CLI 인스턴스에서 사용 (2) 알림에 소스 Mac 식별자 포함 |
| P2-6 | 사용자로서, macOS Shortcuts에서 Watch 알림을 보내고 싶다 | (1) Shortcuts 앱에 ding 액션 노출 (2) 제목, 본문 파라미터 지원 |
| P2-7 | 사용자로서, 알림 피로를 방지하기 위한 쿨다운/DND 설정이 필요하다 | (1) 동일 명령 반복 시 배치 알림 (2) 시간당 최대 알림 수 제한 (3) DND 스케줄 |

---

## 6. Solution Overview

### 시스템 아키텍처

```
┌─────────────────────────────────────────────────┐
│                    macOS                         │
│                                                  │
│   $ ding wait -- npm run build                   │
│   $ ding notify "deploy done" -s success         │
│                                                  │
│   ┌──────────────────────────────────────┐       │
│   │           ding CLI                   │       │
│   │  (Swift, ArgumentParser, Homebrew)   │       │
│   └──────────────┬───────────────────────┘       │
└──────────────────┼───────────────────────────────┘
                   │ HTTPS POST (JSON)
                   ▼
┌──────────────────────────────────────────────────┐
│        Cloudflare Workers Relay (~60 LOC)         │
│                                                   │
│  • JSON 수신 → APNs visible push 변환              │
│  • ES256 JWT 생성 (20분 캐싱)                       │
│  • 무료 티어: 100K req/day                          │
└──────────────────┬────────────────────────────────┘
                   │ HTTP/2 (APNs)
                   ▼
┌──────────────────────────────────────────────────┐
│              Apple Push Notification service       │
└──────────────────┬────────────────────────────────┘
                   │ visible push
                   ▼
┌──────────────────────────────────────────────────┐
│              iPhone (iOS 앱)                       │
│                                                   │
│  • APNs 디바이스 토큰 등록                           │
│  • 시스템 알림으로 표시                               │
│  • 별도 앱 로직 불필요                               │
└──────────────────┬────────────────────────────────┘
                   │ iOS 알림 미러링 (자동)
                   ▼
┌──────────────────────────────────────────────────┐
│              Apple Watch                           │
│                                                   │
│  • iPhone 잠금 시 자동 미러링                        │
│  • 시스템 햅틱 + 알림 배너                           │
│  • Watch 전용 앱 불필요 (v1)                        │
└──────────────────────────────────────────────────┘
```

### 핵심 설계 결정

**1. APNs Visible Push + 알림 미러링 (PoC 검증 완료)**

원래 계획했던 silent push + WatchConnectivity 대신, visible push의 iOS 알림 미러링을 활용한다. 이는 PoC에서 100% 전달 성공률을 보여줬으며, Watch 전용 앱 코드가 전혀 필요하지 않다.

| 비교 | 원래 계획 (silent + WC) | 최종 (visible + 미러링) |
|------|------------------------|----------------------|
| iPhone 백그라운드 전달 | 불안정 (~0% after 5min) | **100%** |
| Watch 전달 메커니즘 | WCSession (코드 필요) | iOS 미러링 (자동) |
| 필요한 앱 수 | 3개 (Mac, iOS, watchOS) | **1개 (iOS만, 최소)** |
| 총 코드량 | ~2000 LOC | **~300 LOC** |
| E2E 레이턴시 | 1-10초 (가변) | **1-3초 (안정)** |

**2. Mac 앱 제거, CLI-Only**

PoC에서 Mac 메뉴바 앱의 IPC 라우팅이 불필요한 복잡성임이 확인되었다. CLI가 직접 릴레이 서버에 HTTP POST를 보내는 것이 가장 단순하고 안정적이다.

- 제거: Mac 앱, Unix domain socket, IPC, Bonjour/TCP, 연결 상태 관리
- 남은 것: CLI 1개 (`ding`) + HTTP POST

**3. Cloudflare Workers 릴레이**

자체 서버 대신 Cloudflare Workers를 사용하여:
- 무료 티어 100K req/day (개인 개발자 용도로 충분)
- 전 세계 엣지에서 실행 → 낮은 레이턴시
- 서버 관리 불필요
- ~60줄 TypeScript

**4. JWT 캐싱 (PoC에서 발견한 문제 해결)**

APNs는 JWT 토큰 변경 빈도를 제한한다 (`TooManyProviderTokenUpdates`). `iat`을 20분 단위로 라운딩하여 모든 Worker isolate가 동일한 JWT를 생성하도록 한다.

### CLI 인터페이스

```bash
# 명령 래핑 — 완료 시 Watch 알림
ding wait -- npm run build
ding wait -- cargo test
ding wait -- python train.py
ding wait --title "ML Training" -- python train.py

# 직접 알림 전송
ding notify "배포 완료"
ding notify "빌드 실패" --status failure --title "CI/CD"

# 테스트 (4가지 status 타입 순차 전송)
ding test

# 상태 확인
ding status

# 초기 설정
ding setup
```

### 알림 페이로드

```json
{
  "id": "uuid",
  "title": "Command Succeeded",
  "body": "npm run build (exit 0, 45.2s)",
  "status": "success",
  "command": "npm run build",
  "exitCode": 0,
  "duration": 45.2,
  "timestamp": "2026-03-11T14:30:00Z"
}
```

### 기술 스택

| 컴포넌트 | 기술 | 코드량 |
|---------|------|-------|
| CLI (`ding`) | Swift, ArgumentParser | ~200 LOC |
| APNs 릴레이 | Cloudflare Workers, TypeScript | ~60 LOC |
| iOS 컴패니언 앱 | Swift, SwiftUI (최소) | ~100 LOC |
| watchOS 앱 | 불필요 (v1) — iOS 미러링 사용 | 0 LOC |
| 배포 | Homebrew (CLI), TestFlight/App Store (iOS) | — |

**총 ~360 LOC**로 전체 시스템 구현 가능.

### 온보딩 플로우

```
1. brew install ding                         (30초)
2. App Store에서 ding iOS 앱 설치              (30초)
3. iOS 앱 열기 → 알림 권한 허용 → 디바이스 토큰 표시  (15초)
4. ding setup <디바이스 토큰>                   (10초)
5. ding test                                 (5초)
   → Watch에서 테스트 알림 4개 도착 확인
```

총 소요 시간: ~90초

**개선 가능**: v1.1에서 QR 코드 스캔 또는 iCloud 기반 자동 토큰 동기화로 step 3-4 간소화

---

## 7. Open Questions

| # | Question | Owner | Deadline |
|---|----------|-------|----------|
| 1 | **디바이스 토큰 등록/관리 UX**: CLI에서 긴 토큰을 수동 입력하는 것은 불편하다. QR 코드? 딥링크? iCloud KeyValue Store? 최적의 토큰 전달 메커니즘은? | 엔지니어링 | MVP 시작 1주차 |
| 2 | **릴레이 서버 인증**: 현재 릴레이는 인증 없이 누구나 POST 가능하다. API 키 기반 인증이 필요한가? 무료 티어 남용 방지 전략은? | 엔지니어링 | MVP 시작 2주차 |
| 3 | **다중 디바이스 지원**: 릴레이에 하드코딩된 단일 DEVICE_TOKEN 대신, 사용자별 토큰 관리가 필요하다. KV 스토어(Cloudflare KV)? DB? | 엔지니어링 | MVP 시작 2주차 |
| 4 | **수익 모델**: 무료 (오픈소스)? 프리미엄 ($4.99 일회성)? 구독 ($1.99/월)? iOS 앱을 유료로 할 경우 CLI는 무료 유지 가능한가? | PM/비즈니스 | Phase 2 시작 전 |
| 5 | **APNs sandbox → production 전환**: 현재 PoC는 sandbox APNs 사용. App Store 배포 시 production APNs로 전환 절차와 인증서 관리 전략은? | 엔지니어링 | App Store 제출 전 |
| 6 | **알림 그룹핑**: iOS가 동일 앱의 알림을 자동 그룹핑하는데, 10개 연속 알림 시 Watch에서의 표시 방식은 최적인가? Thread identifier 활용 필요성? | 디자인 | MVP 테스트 중 |

---

## 8. Timeline & Phasing

### Phase 1: MVP (4주)

**목표**: `ding wait` + `ding notify`가 동작하는 최소 제품을 Homebrew + App Store에 배포

| 주차 | 마일스톤 | 상세 |
|------|---------|------|
| 1 | CLI 완성 + 릴레이 프로덕션 배포 | PoC CLI 코드 정리, 릴레이 인증 추가, APNs production 전환, `ding setup` 구현 |
| 2 | iOS 앱 프로덕션 | 토큰 등록 UX 개선 (QR/딥링크), 알림 카테고리·사운드 설정, App Store 제출 준비 |
| 3 | Homebrew 배포 + 통합 테스트 | Homebrew Formula/Tap 작성, E2E 테스트 (다양한 시나리오), 엣지 케이스 처리 |
| 4 | 베타 + 출시 | TestFlight 베타 (5-10명), 피드백 반영, Homebrew + App Store 동시 출시 |

**Phase 1 산출물**:
- `ding` CLI (Homebrew)
- iOS 컴패니언 앱 (App Store)
- Cloudflare Workers 릴레이 (프로덕션)
- 랜딩 페이지 + 설치 가이드

### Phase 2: 확장 (4주)

| 주차 | 마일스톤 | 상세 |
|------|---------|------|
| 5-6 | 셸 자동 훅 + 웹훅 | `install-hook` 명령 (zsh/bash), 릴레이 웹훅 엔드포인트 (CI/CD 연동) |
| 7 | Watch 전용 앱 | 커스텀 햅틱 (성공/실패 구분), Rich notification UI, 알림 히스토리 |
| 8 | 다중 사용자 지원 | 릴레이에 사용자 계정/API 키 시스템, Cloudflare KV 기반 토큰 관리 |

### Phase 3: 성장 (4주)

| 주차 | 마일스톤 | 상세 |
|------|---------|------|
| 9-10 | 피드백 반영 + 마케팅 | 사용자 피드백 기반 우선순위 조정, Product Hunt/HN/Reddit 런칭 |
| 11-12 | 플러그인 시스템 | 파일 감시, 프로세스 감시, 플러그인 인터페이스, `ding watch` 명령 |

### 의존성

```
Phase 1 (4주): 독립 실행 가능 — PoC 코드 기반
  └── Phase 2 (4주): Phase 1 사용자 피드백 반영
       └── Phase 3 (4주): Phase 2 안정화 후

외부 의존성:
- Apple Developer Program 계정 ($99/year) — APNs, App Store
- Cloudflare 계정 (무료 티어)
- Homebrew Tap 또는 core formula 등록
```

---

## Appendix: PoC에서 해결된 원래 PRD의 위험 요소

| 원래 위험 | 상태 | 해결 방법 |
|----------|------|----------|
| T1: iOS 백그라운드 서스펜션 (80% 확률) | **해결됨** | Visible push는 OS 레벨에서 전달 — 앱 상태 무관 |
| T2: 3-hop 체인 3초 지연 목표 미달 (70%) | **해결됨** | 1-3초 달성. 3-hop → 실질적 1-hop (APNs가 처리) |
| T3: 3개 앱 온보딩 마찰 (70%) | **대폭 완화** | Mac 앱 제거, Watch 앱 불필요 (v1). CLI + iOS 앱만 설치 |
| T4: "잊어버린 iPhone" 문제 (50%) | **해결됨** | APNs는 iPhone 위치/상태 무관하게 전달 |
| T5: macOS 샌드박스 충돌 (50%) | **해당 없음** | Mac 앱 제거. CLI는 샌드박스 밖에서 동작 |
| E1: Apple이 네이티브 연동 발표 (코끼리) | **여전히 유효** | 단, 극도로 단순한 아키텍처 덕분에 개발 투자 리스크 최소화 |
| E3: iPhone 필수 의존성 (코끼리) | **완화** | iPhone 앱이 "설치하고 잊는" 수준으로 단순화. 사용자가 의식할 필요 없음 |

---

*Generated: 2026-03-11*
*Based on: PoC 결과 ([architecture-decision.md](./Docs/architecture-decision.md), [latency-report.md](./Docs/latency-report.md)), 원래 PRD ([prd-watchtask.md](./prd-watchtask.md))*
