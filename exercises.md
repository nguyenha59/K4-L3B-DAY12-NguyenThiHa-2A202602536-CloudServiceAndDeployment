# Phiếu Phản Ánh — K4 Level 3B, Ngày 12

> **Bài làm cá nhân.** Trả lời bằng lời của chính bạn, dựa trên những gì bạn
> quan sát được khi chạy code — không sao chép đáp án của người khác.
>
> Cách trả lời: thay dòng placeholder dưới mỗi câu bằng câu trả lời.
> `grade.py` đếm số câu đã trả lời (15 điểm cho 10 câu).
>
> Họ và tên: Nguyễn Thị Hạ  Mã học viên: 2A202602536

---

### Câu 1 — Fail fast (CP1)

Trong `Settings`, `agent_api_key` không có giá trị mặc định nên app chết ngay
khi khởi động nếu thiếu biến môi trường. Hãy mô tả một tình huống cụ thể mà
việc "chết sớm" này cứu bạn, so với việc để mặc định `"changeme"`.

> Nếu mặc định là `"changeme"`, khi deploy lên Render mà mình quên set `AGENT_API_KEY` trong dashboard thì service vẫn lên "xanh", health check vẫn 200, và ai đọc repo công khai cũng biết khóa `changeme` → gọi `/ask` thoải mái, đốt hết budget. Với fail fast, container chết ngay lúc khởi động với lỗi validation thiếu biến, Render báo deploy fail, mình thấy lỗi trong log và set biến trước khi service nhận request nào.

---

### Câu 2 — Log cho máy đọc (CP1)

Chạy service và gọi `/ask` vài lần. Dán một dòng log JSON bạn thu được, rồi
nêu **hai** việc bạn làm được với dòng log đó mà `print("đã trả lời xong")`
không làm được.

> Dòng log thật khi chạy 3 instance:
> `{"event": "ask_completed", "level": "info", "timestamp": "2026-09-29T04:24:30.589486+00:00", "user_id": "scale-2249", "tokens_in": 80, "tokens_out": 43, "cost_usd": 3.78e-05}`
>
> (1) Lọc/đếm theo trường: ví dụ `grep ask_completed | jq 'select(.user_id=="scale-2249")'` hoặc để log platform (Render, Loki...) lọc theo `user_id` để xem một người dùng đã hỏi bao nhiêu lần. (2) Cộng dồn `cost_usd`/`tokens_in` để tính chi phí theo ngày hoặc theo user và đặt cảnh báo khi vượt ngưỡng. `print("đã trả lời xong")` không có user, không có số liệu, không có timestamp chuẩn nên máy không parse được.

---

### Câu 3 — Kích thước image (CP2)

Build cả hai phiên bản và ghi lại số đo thật:

```bash
docker build -f <Dockerfile-1-stage> -t agent:single .
docker build -t agent:multi .
docker images | grep agent
```

| Bản | Dung lượng |
|-----|-----------|
| 1 stage (bản đầu) | 1.73 GB (446 MB nén) |
| Multi-stage | 271 MB (64 MB nén) |

Giải thích: phần dung lượng chênh lệch đó là những gì?

> Chênh ~1.46 GB. Bản 1 stage dùng `python:3.11` đầy đủ (dựa trên Debian đầy đủ, kèm gcc, build-essential, header dev, git, các thư viện hệ thống không dùng tới) và giữ cả cache pip. Bản multi-stage dùng `python:3.11-slim`, stage builder cài package với `--no-cache-dir --prefix=/install`, runtime chỉ copy thư mục `/install` + code `app/`, `utils/` sang — không có compiler, không có cache pip, không có file thừa trong repo (nhờ `.dockerignore`).

---

### Câu 4 — Thứ tự lệnh trong Dockerfile (CP2)

Sửa một ký tự trong `app/main.py` rồi build lại. Với Dockerfile của bạn, những
layer nào được dùng lại từ cache, layer nào phải chạy lại? Nếu bạn đặt
`COPY . .` lên trước `RUN pip install` thì kết quả khác thế nào?

> Mình thêm 1 dòng comment vào `app/main.py` rồi build với `--progress=plain`: các bước `WORKDIR`, `COPY requirements.txt`, `RUN pip install`, `COPY --from=builder /install`, `RUN useradd` đều `CACHED`; chỉ `COPY app ./app` (2.1s) và `COPY utils ./utils` chạy lại. Build xong trong vài giây. Nếu đặt `COPY . .` trước `RUN pip install` thì mọi thay đổi code làm layer COPY đổi hash → toàn bộ layer sau nó, gồm cả `pip install`, mất cache và phải tải/cài lại thư viện mỗi lần build.

---

### Câu 5 — Vì sao không chạy bằng root (CP2)

Container mặc định chạy bằng root. Mô tả chuỗi sự kiện dẫn từ "một lỗ hổng
trong code Python của bạn" tới "kẻ tấn công có quyền cao trên máy host", và
lệnh `USER` cắt đứt chuỗi đó ở chỗ nào.

> Chuỗi: lỗ hổng trong code (ví dụ RCE qua deserialize/`eval` input, hoặc path traversal ghi file) → kẻ tấn công chạy lệnh trong container với quyền của process → nếu process là root (UID 0) thì họ đọc/sửa được mọi file trong container, cài công cụ, và vì UID 0 trong container là UID 0 trên host (không dùng user namespace) nên khi gặp thêm một lỗi cấu hình (mount `/var/run/docker.sock`, volume của host, `--privileged`, lỗ hổng kernel/runc) họ thoát ra ngoài với quyền root trên host. `USER appuser` (UID 10001) cắt ở bước thứ hai: process chỉ có quyền của user thường, không ghi được file hệ thống, không cài package, và nếu có thoát ra thì cũng chỉ là UID 10001 không có quyền gì trên host.

---

### Câu 6 — Cửa sổ trượt (CP3)

Rate limit của bạn dùng sliding window 60 giây. Nếu thay bằng cách đếm theo
phút đồng hồ (reset lúc giây 00), một người dùng có thể gửi tối đa bao nhiêu
request trong 2 giây liên tiếp khi hạn mức là 10/phút? Giải thích cách đạt được
con số đó.

> Tối đa 20 request. Người dùng gửi 10 request ở giây 59 của phút thứ nhất (counter phút đó = 10, vẫn hợp lệ), đến giây 00 counter reset về 0, gửi tiếp 10 request ở giây 00–01 của phút mới. Tổng 20 request trong khoảng 2 giây, gấp đôi hạn mức. Với sliding window 60 giây, lúc giây 00 cửa sổ vẫn chứa 10 request vừa gửi ở giây 59 nên request thứ 11 bị trả 429.

---

### Câu 7 — Rate limit và cost guard (CP3)

Hai cơ chế này khác nhau ở điểm nào? Cho một tình huống mà rate limit cho qua
nhưng cost guard phải chặn, và một tình huống ngược lại.

> Rate limit giới hạn **số request trong một khoảng thời gian** (10/phút) để chống spam/lạm dụng tức thời; cost guard giới hạn **tổng tiền đã tiêu** (10 USD/tháng) theo token thực tế. Rate limit cho qua nhưng cost guard chặn: người dùng gửi đều 5 câu/phút nhưng mỗi câu là prompt rất dài, cả tháng cộng lại vượt 10 USD. Ngược lại: người dùng bắn 15 câu "hi" trong 10 giây — chi phí gần như bằng 0, cost guard không chặn, nhưng từ request thứ 11 rate limit trả 429.

---

### Câu 8 — /health khác /ready (CP4)

Nếu gộp hai endpoint làm một và cho nó kiểm tra Redis, chuyện gì xảy ra với cụm
3 container khi Redis mất kết nối 30 giây? Trả lời theo đúng thứ tự sự kiện.

> (1) Redis mất kết nối → endpoint gộp ở cả 3 container đều trả 503. (2) Orchestrator dùng endpoint này làm liveness nên sau vài lần check fail liên tiếp nó coi cả 3 container là "chết" và kill/restart cả 3 cùng lúc. (3) Trong lúc restart không container nào nhận request → toàn bộ service down, kể cả những request không cần Redis. (4) Container mới lên vẫn thấy Redis mất → lại fail → restart loop cho đến khi Redis về, rồi còn mất thêm thời gian khởi động. Tách ra thì `/health` (liveness) vẫn 200 nên không bị kill, chỉ `/ready` 503 để load balancer tạm ngừng gửi traffic; Redis về sau 30 giây là `/ready` 200 lại ngay, không container nào phải restart.

---

### Câu 9 — Stateless (CP4)

Chạy `docker compose up --scale agent=3` rồi gọi `/ask` nhiều lần với cùng một
`X-User-Id`. Quan sát `history_length` trong response. Nếu lịch sử được lưu
trong một dict Python thay vì Redis, bạn sẽ thấy con số đó thay đổi thế nào?

> Mình chạy 3 agent sau nginx, gọi `/ask` 6 lần với cùng `X-User-Id: scale-2249`. Log cho thấy nginx chia đều: agent-1, agent-2, agent-3 mỗi container nhận 2 request, nhưng `history_length` vẫn tăng đều `0, 2, 4, 6, 8, 10` vì lịch sử nằm chung trong Redis. Nếu lưu trong dict Python thì mỗi container có dict riêng: con số sẽ nhảy lung tung theo container nhận request, kiểu `0, 0, 0, 2, 2, 2` (round-robin), người dùng thấy agent "quên" hội thoại, và mất hết khi container restart.

---

### Câu 10 — Deploy thật (CP5)

Ghi lại **một** lỗi bạn gặp khi deploy lên cloud (build fail, health check
timeout, sai REDIS_URL, app không đọc `$PORT`...): thông báo lỗi là gì, bạn
tìm ra nguyên nhân bằng cách nào, và sửa ra sao?

> *Câu trả lời của bạn*
