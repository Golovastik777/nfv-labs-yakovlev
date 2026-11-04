# ЛР4. SDN: OpenFlow 1.3, Open vSwitch и OpenDaylight

## Персональные параметры

| Параметр | Значение |
| --- | --- |
| Номер ИСУ | 315907 |
| `STUDENT` | `yakovlev` |
| `N` | `7` |
| Management-подсеть / адрес ODL | `10.104.7.0/24` / `10.104.7.100` |
| s1 / s2 (mgmt) | `10.104.7.11` / `10.104.7.12` |
| Хосты h1, h2, h3 | `10.7.4.1`, `10.7.4.2`, `10.7.4.3` (/24) |
| Префикс ID потоков | `yakovlev-` |
| Приоритет ACL | `507` (500 + 7) |
| Где работаю | локально: Colima на Mac (ВМ Ubuntu 24.04 aarch64, 4 vCPU, 8 ГБ) |

## Стенд

- Docker 29.5.2 в ВМ Colima, containerlab 0.82.0 запускается из официального образа `ghcr.io/srl-labs/clab` (обёртка `containerlab` в [scripts/env.sh](scripts/env.sh) включается, только если бинарника нет).
- Образы `odl:chromium` (ODL Karaf 0.24.0, Java 21), `ovs-lab:latest`, `lab-tools:1.0` собраны из `images/` курса под arm64: всё на Java, Debian и Alpine, x86 не нужен.
- Все команды выполняются внутри ВМ (`colima ssh`): management-сеть `10.104.7.0/24` существует только там.
- Полные выводы всех шагов лежат в [logs/](logs/).

## Схема

```
  Плоскость управления (out-of-band, management-сеть 10.104.7.0/24, eth0)

                    ┌───────────────────────────────────────┐
                    │ odl  10.104.7.100                     │
                    │ OpenFlow 1.3 :6653 · RESTCONF :8181   │
                    └──────┬─────────────────────────┬──────┘
                 tcp:6653  │                         │  tcp:6653
                eth0 10.104.7.11            eth0 10.104.7.12
 ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┼ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┼ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─
  Плоскость данных (br0, datapath netdev, fail-mode=secure, номер порта = номер ethX)

                    ┌──────┴──────┐           ┌──────┴──────┐
  h1 10.7.4.1 eth1 ─┤1  s1     2  ├───────────┤2  s2     1  ├─ eth1 h2 10.7.4.2
                    │ openflow:1  │           │ openflow:2  │
                    └─────────────┘           │          3  ├─ eth1 h3 10.7.4.3
                                              └─────────────┘
```

| Коммутатор | DPID | Порт OpenFlow | Интерфейс | Куда ведёт |
| --- | --- | --- | --- | --- |
| s1 | `openflow:1` | 1 | eth1 | h1 |
| s1 | `openflow:1` | 2 | eth2 | s2:2 |
| s2 | `openflow:2` | 1 | eth1 | h2 |
| s2 | `openflow:2` | 2 | eth2 | s1:2 |
| s2 | `openflow:2` | 3 | eth3 | h3 |

## Таблица потоков

Все потоки в table 0, файлы лежат в [flows/](flows/), имя файла = id без префикса `yakovlev-`.

| ID потока | Коммутатор | Приоритет | Match | Действие |
| --- | --- | --- | --- | --- |
| `yakovlev-s1-1to2` | s1 | 200 | in-port 1 | output 2 |
| `yakovlev-s1-2to1` | s1 | 200 | in-port 2 | output 1 |
| `yakovlev-s2-to-h2-ip` | s2 | 200 | in-port 2, IPv4, dst `10.7.4.2/32` | output 1 |
| `yakovlev-s2-to-h2-arp` | s2 | 200 | in-port 2, ARP, target `10.7.4.2/32` | output 1 |
| `yakovlev-s2-to-h3-ip` | s2 | 200 | in-port 2, IPv4, dst `10.7.4.3/32` | output 3 |
| `yakovlev-s2-to-h3-arp` | s2 | 200 | in-port 2, ARP, target `10.7.4.3/32` | output 3 |
| `yakovlev-s2-1to2` | s2 | 200 | in-port 1 | output 2 |
| `yakovlev-s2-3to2` | s2 | 200 | in-port 3 | output 2 |
| `yakovlev-acl-icmp-h3` | s1 | 507 | in-port 1, IPv4, ip-proto 1, dst `10.7.4.3/32` | drop |
| table-miss (ставит ODL, cookie `0xa`) | s1, s2 | 0 | любой пакет | CONTROLLER:65535 |

Между h2 и h3 потоков нет намеренно: всё, что приходит с портов 1 и 3 коммутатора s2, уходит в сторону s1.

## Запуск

```bash
colima ssh                            # на сервере преподавателя не нужно
cd ~/nfv-labs-yakovlev/lab4           # в ВМ это ссылка на ту же папку на Mac
source scripts/env.sh                 # STUDENT, N, ODL, odl_get/put_flow/del_flow
containerlab deploy -t lab4.clab.yml
docker exec -t clab-$STUDENT-l4-odl /opt/odl/bin/client -r 30 -d 5 \
  "feature:install odl-openflowplugin-flow-services-rest odl-openflowplugin-app-table-miss-enforcer odl-restconf-openapi"
docker exec -i -e DPID=1 -e ODL_IP=10.104.$N.100 clab-$STUDENT-l4-s1 sh < scripts/ovs-setup.sh
docker exec -i -e DPID=2 -e ODL_IP=10.104.$N.100 clab-$STUDENT-l4-s2 sh < scripts/ovs-setup.sh
```

Потоки:

```bash
scripts/push-flows.sh 's*'            # этап 3: все потоки s1-* и s2-* (без ACL)
scripts/push-flows.sh acl-icmp-h3     # этап 4.1: ACL
scripts/push-flows.sh -d acl-icmp-h3  # этап 4.2: удалить ACL (ожидается 204)
scripts/push-flows.sh                 # все файлы из flows/, включая ACL
```

Скрипт проверяет, что `id` в файле равен `yakovlev-<имя файла>`, номер коммутатора берёт из `match.in-port` (`openflow:<dpid>:<порт>`) и возвращает ненулевой код, если хоть один запрос не получил 200/201/204.

Замечания по запуску:

- `-t` у `docker exec` для клиента Karaf обязателен: без TTY клиент печатает `Closed` и ничего не выполняет. `-r 30 -d 5` — до 30 попыток подключения с паузой 5 с, вместо ручного `sleep 30`.
- Исключение `Could not start JMX connector server` в `docker logs` контейнера ODL безвредно: не поднимается только RMI-коннектор для мониторинга.
- Первый PUT потока даёт 201, повторный с теми же данными — 204.

## Ответы на вопросы

### 1.1. Как называется схема управления через management-сеть?

Это **out-of-band** управление: канал OpenFlow идёт по отдельной сети (`eth0`, 10.104.7.0/24), а не через порты данных. Поэтому в `ovs-setup.sh` стоит `disable-in-band=true`.

Почему в production его предпочитают in-band:

- Канал управления не зависит от плоскости данных. Ошибочный поток, петля, перегрузка или отказ порта данных не отрезают коммутатор от контроллера, и это можно исправить с контроллера.
- Нет проблемы курицы и яйца: при in-band коммутатору нужны правила пересылки, чтобы добраться до контроллера, который эти правила и ставит. OVS решает это скрытыми in-band-потоками, которые не видны в `dump-flows` и мешают отлаживать ACL.
- Изоляция и безопасность: хосты из плоскости данных не видят трафик OpenFlow и не могут атаковать контроллер или порт 6653.
- Предсказуемость: полосу и задержку канала управления не съедает пользовательский трафик.

### 1.2. Что делает `table-miss-enforcer`?

При подключении каждого коммутатора он ставит в table 0 поток table-miss: приоритет 0, пустой match, действие `CONTROLLER` (в `dump-flows`: `cookie=0xa, … send_flow_rem priority=0 actions=CONTROLLER:65535`). В operational-хранилище ODL этот поток виден под сгенерированным id `#UF$TABLE*0-1`, в config его нет.

Зачем: в OpenFlow 1.3, в отличие от 1.0, пакет без совпадений по умолчанию **отбрасывается**, и packet-in не отправляется. Без явного table-miss контроллер не видит трафик: не работают LLDP-обнаружение топологии, учёт хостов и реактивные приложения вроде L2Switch.

### 2.3. Почему без потоков ping не проходит?

h1 сначала шлёт широковещательный ARP-запрос «кто такой 10.7.4.2». На s1 есть только поток table-miss, поэтому кадр уходит контроллеру как packet-in (счётчик `n_packets` у table-miss растёт). В ODL установлены только OpenFlow Plugin, table-miss-enforcer и RESTCONF, и ни одно приложение не обрабатывает packet-in. Контроллер принимает пакет и ничего не делает: нет packet-out, нет flow-mod. Сам коммутатор в режиме `fail-mode=secure` пересылать не будет (никакого `NORMAL`), поэтому ARP-запрос умирает на s1, h1 не получает MAC адресата, и ping теряет 100% пакетов.

Наблюдение ([logs/2.3-no-flows.txt](logs/2.3-no-flows.txt)): после `ping -c 2` счётчик table-miss на s1 вырос с `n_packets=6` до `9`, а `ip neigh` на h1 показывает `10.7.4.2 dev eth1 INCOMPLETE`.

### 3.3. Чем config-хранилище отличается от operational? Что будет после `ovs-ofctl del-flows`?

- **config** — намерение: то, что записали через RESTCONF (`PUT`). Хранится в ODL персистентно, переживает перезапуск контроллера и служит источником для Forwarding Rules Manager, который превращает изменения в flow-mod на коммутатор.
- **operational** (`content=nonconfig`) — фактическое состояние, которое коммутатор сообщает на периодические запросы статистики: потоки, которые реально стоят в таблице, со счётчиками `packet-count`/`byte-count`. Там есть и потоки, которых нет в config (например table-miss, их id имеют вид `#UF$TABLE*0-…`). Данные обновляются раз в несколько секунд, поэтому отстают от `ovs-ofctl`.

`ovs-ofctl del-flows br0` удаляет все потоки прямо на коммутаторе, мимо контроллера, включая table-miss. Проверено на s2 ([logs/3.3-del-flows.txt](logs/3.3-del-flows.txt)):

- таблица s2 сразу пустая, ping h1 → h2 перестаёт проходить;
- через 30 с в config по-прежнему 6 потоков `yakovlev-s2-*`, а operational пуст (`[]`): ODL не сравнивает состояние постоянно и сам потоки не вернул;
- после переподключения (`ovs-vsctl del-controller br0`, затем `set-controller`) reconciliation за несколько секунд вернул все 6 потоков и table-miss, со счётчиками `n_packets=0`, и ping снова прошёл.

### 5.3. Какой режим безопаснее и какой надёжнее? Что такое reconciliation?

- **secure** безопаснее: без контроллера коммутатор никогда не пересылает трафик по своей логике, политика (в том числе ACL) не обходится. С проактивными потоками он ещё и устойчив: уже установленные правила продолжают работать, недоступны только новые решения контроллера.
- **standalone** надёжнее с точки зрения доступности: при потере контроллера сеть работает как обычный обучающийся L2-коммутатор, даже для пар, правил для которых нет. Цена такая: все OpenFlow-потоки, включая ACL, стираются, сегментация и политика пропадают, а в топологии с петлями без STP возможен широковещательный шторм.
- **Reconciliation** — синхронизация состояния коммутатора с config-хранилищем контроллера при (пере)подключении: Forwarding Rules Manager читает из config потоки, группы и метры для этого узла и заново отправляет их на коммутатор, а table-miss-enforcer снова ставит table-miss. После возвращения ODL потоки восстановились (config-хранилище персистентно и пережило `docker stop/start`): через ~9 с после `docker start` на s2 снова 6 потоков, на s1 два, плюс table-miss. Счётчики начались с нуля, потому что это заново установленные потоки. ACL не вернулся, потому что его удалили из config на этапе 4.2.

## Этап 4. ACL и статистика

С ACL ICMP от h1 к h3 отбрасывается на s1 (100% потерь), ARP и TCP проходят: `curl` к `http://10.7.4.3:8080/` даёт 200, ping h1 → h2 работает ([logs/4.1-acl.txt](logs/4.1-acl.txt)).

После `ping -c 2` на h3 ([logs/4.2-stats.txt](logs/4.2-stats.txt)):

- REST: `"packet-count": "2"`, `"byte-count": "196"`;
- OVS: `priority=507,icmp,in_port=1,nw_dst=10.7.4.3 actions=drop`, `n_packets=2, n_bytes=196`.

Счётчик равен числу отправленных ping: отбрасываются только echo request, ответов не возникает. 196 байт = 2 × 98 (56 данных + 8 ICMP + 20 IP + 14 Ethernet). Значение в REST обновляется периодическим опросом статистики и может отставать от `ovs-ofctl` на несколько секунд. `del_flow 1 yakovlev-acl-icmp-h3` вернул 204, после чего ping h1 → h3 снова прошёл.

## Этап 5. Наблюдения при отказе контроллера

| Шаг | Канал управления | Потоки на s1/s2 | Трафик |
| --- | --- | --- | --- |
| 5.1 `docker stop odl`, secure | строка `is_connected: true` пропала, OVS переподключается в фоне | все проактивные потоки и table-miss на месте, счётчики продолжают расти | h1 → h2 (3/3) и h1 → h3 (2/2) работают по старым потокам; h2 → h3 — 100% потерь |
| 5.2 standalone, контроллера нет | не подключён | OVS вошёл в fail-open (в логе: `… for 69 seconds, failing open` — столько прошло с потери контроллера; порог 3 × 5 с уже был превышен, поэтому переход случился сразу после смены режима): **стёр все OpenFlow-потоки**, `ovs-ofctl dump-flows` пустой; `ovs-appctl bridge/dump-flows` показывает скрытый `priority=15790320,actions=NORMAL` | работает всё, включая h2 → h3 (3/3): коммутатор стал обучающимся L2-коммутатором, `fdb/show` выучил MAC на портах 1, 2, 3; ACL бы не действовал |
| 5.3 снова secure, ODL ещё выключен | не подключён | fail-open снят вместе со скрытым NORMAL-потоком, своих потоков уже нет, таблица пуста | h1 → h2 — 100% потерь: secure + пустая таблица = всё отбрасывается |
| 5.3 `docker start odl`, 60 с | `is_connected: true` | reconciliation через ~9 с после старта: 6 потоков на s2, 2 на s1, table-miss; счётчики с нуля, ACL нет | h1 → h2, h1 → h3 снова работают; h2 ↔ h3 нет |

Полные выводы: [5.1](logs/5.1-secure.txt), [5.2](logs/5.2-standalone.txt), [5.3](logs/5.3-recovery.txt). Скрытый fail-open поток виден только через `ovs-appctl`:

```bash
docker exec clab-$STUDENT-l4-s2 ovs-appctl bridge/dump-flows br0
```

## Финальный артефакт

После reconciliation счётчики потоков обнулены, а в артефакте нужны ненулевые `n_packets`. Поэтому перед командой из этапа 6 прогоните трафик:

```bash
docker exec clab-$STUDENT-l4-h1 ping -c 3 10.$N.4.2
docker exec clab-$STUDENT-l4-h1 ping -c 3 10.$N.4.3
```

Результат прогона: [logs/6-artifact.txt](logs/6-artifact.txt) — `is_connected: true`, `fail_mode: secure`, `["openflow:1","openflow:2"]`, потоки с `10.7.4.x` и ненулевыми `n_packets`, ping h1 → h3 2/2, `igoryakovlev@colima`.
