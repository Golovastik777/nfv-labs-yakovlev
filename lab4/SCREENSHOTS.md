# ЛР4: команды для скриншотов

11 скриншотов. Каждый блок вставляется в терминал целиком, скрин снимается после того, как вывод закончился. Блоки идут по порядку: каждый следующий опирается на состояние после предыдущего, а после последнего стенд оказывается в том же состоянии, что и до первого.

## Подготовка

Терминал пошире и повыше: в некоторых блоках 40+ строк. Перед каждым блоком очищайте экран через Ctrl+L и только потом вставляйте блок. Тогда на скрине будут и команды, и вывод, а верхняя строка не обрежется.

```bash
colima ssh
```

```bash
cd ~/nfv-labs-yakovlev/lab4 && source scripts/env.sh && echo "$STUDENT $N $ODL"
```

Должно вывестись `yakovlev 7 http://10.104.7.100:8181`. Стенд должен быть запущен (`containerlab inspect -t lab4.clab.yml`, все 6 узлов `running`). Если стенд был удалён, разверните его заново по разделу «Запуск» в [README.md](README.md).

## Соответствие требованиям

| Скрин | Что показывает | Требование к защите / раздел PDF |
| --- | --- | --- |
| 1 | узлы стенда, фичи ODL, порты 6653/8181 | этап 1 |
| 2 | `ovs-vsctl show` на s1 и s2, номера портов, инвентарь ODL | защита п.1 |
| 3 | ping до установки потоков | защита п.2 |
| 4 | установка потоков и ping после | защита п.2 |
| 5 | `dump-flows` на s1 и s2, потоки в config ODL | защита п.2 |
| 6 | ACL: ICMP заблокирован, HTTP 200, h2 доступен | защита п.3 |
| 7 | счётчик ACL растёт, статистика REST, удаление ACL | защита п.3 |
| 8 | 5.1: контроллер выключен, режим `secure` | защита п.4 |
| 9 | 5.2: режим `standalone`, fail-open | защита п.4 |
| 10 | 5.3: возврат контроллера, reconciliation | защита п.4 |
| 11 | финальный артефакт | этап 6 |

---

## Скрин 1. Этап 1: стенд и приложения ODL

```bash
containerlab inspect -t lab4.clab.yml
docker exec -t clab-$STUDENT-l4-odl /opt/odl/bin/client "feature:list -i" | grep -E "openflowplugin-flow-services-rest|table-miss|restconf-openapi"
docker exec clab-$STUDENT-l4-odl bash -c 'for p in 6653 8181; do (echo > /dev/tcp/127.0.0.1/$p) 2>/dev/null && echo "$p open" || echo "$p closed"; done'
```

Видно: шесть узлов `clab-yakovlev-l4-*` в состоянии `running` с адресами `10.104.7.x`, три фичи в состоянии `Started`, `6653 open`, `8181 open`.

## Скрин 2. Этап 2: подключение OVS и инвентарь ODL

```bash
for s in s1 s2; do echo "== $s"; docker exec clab-$STUDENT-l4-$s ovs-vsctl show; done
docker exec clab-$STUDENT-l4-s2 ovs-ofctl -O OpenFlow13 show br0 | grep -E "^ [0-9]|LOCAL"
odl_get "opendaylight-inventory:nodes?content=nonconfig&depth=3" | jq '."opendaylight-inventory:nodes".node[].id'
```

Видно: `Controller "tcp:10.104.7.100:6653"`, `is_connected: true`, `fail_mode: secure`, `datapath_type: netdev`; порты s2 `1(eth1) 2(eth2) 3(eth3)`; в инвентаре `"openflow:1"` и `"openflow:2"`.

## Скрин 3. Ping до установки потоков

Блок убирает наши потоки через ODL и очищает ARP-кэш h1, чтобы повторить состояние задания 2.3.

```bash
scripts/push-flows.sh -d 's*'
docker exec clab-$STUDENT-l4-h1 ip neigh flush all
sleep 1
docker exec clab-$STUDENT-l4-s1 ovs-ofctl -O OpenFlow13 dump-flows br0
docker exec clab-$STUDENT-l4-h1 ping -c 2 -W 1 10.$N.4.2
docker exec clab-$STUDENT-l4-h1 ip neigh
docker exec clab-$STUDENT-l4-s1 ovs-ofctl -O OpenFlow13 dump-flows br0
```

Видно: восемь `DELETE … 204`, на s1 остался только table-miss (`priority=0 actions=CONTROLLER:65535`), ping `100% packet loss`, `10.7.4.2 … INCOMPLETE`, `n_packets` у table-miss вырос.

## Скрин 4. Установка потоков и ping после

```bash
scripts/push-flows.sh 's*'
sleep 1
docker exec clab-$STUDENT-l4-h1 ping -c 3 10.$N.4.2
docker exec clab-$STUDENT-l4-h1 ping -c 3 10.$N.4.3
```

Видно: восемь `PUT … 201`, оба ping `0% packet loss`.

## Скрин 5. Потоки на коммутаторах и в ODL

```bash
docker exec clab-$STUDENT-l4-s1 ovs-ofctl -O OpenFlow13 dump-flows br0
docker exec clab-$STUDENT-l4-s2 ovs-ofctl -O OpenFlow13 dump-flows br0
odl_get "opendaylight-inventory:nodes/node=openflow%3A2/flow-node-inventory:table=0?content=config" | jq '.[][].flow[].id'
```

Видно: на s1 два потока `priority=200,in_port=…`, на s2 шесть, с `nw_dst=10.7.4.x` и `arp_tpa=10.7.4.x`; ненулевые `n_packets`; в config шесть id `yakovlev-s2-*`.

## Скрин 6. ACL: ICMP блокируется, HTTP проходит

```bash
scripts/push-flows.sh acl-icmp-h3
docker exec -d clab-$STUDENT-l4-h3 python3 -m http.server 8080
sleep 1
docker exec clab-$STUDENT-l4-h1 ping -c 2 -W 1 10.$N.4.3
docker exec clab-$STUDENT-l4-h1 curl -s -o /dev/null -w "%{http_code}\n" http://10.$N.4.3:8080/
docker exec clab-$STUDENT-l4-h1 ping -c 2 10.$N.4.2
```

Видно: `PUT … yakovlev-acl-icmp-h3 201`, ping h3 `100% packet loss`, `200`, ping h2 `0% packet loss`. Если HTTP-сервер на h3 уже запущен, вторая копия молча не стартует, на результат это не влияет.

## Скрин 7. Счётчик ACL растёт, статистика через REST

```bash
docker exec clab-$STUDENT-l4-s1 ovs-ofctl -O OpenFlow13 dump-flows br0 | grep drop
docker exec clab-$STUDENT-l4-h1 ping -c 3 -W 1 10.$N.4.3 | tail -2
sleep 5
odl_get "opendaylight-inventory:nodes/node=openflow%3A1/flow-node-inventory:table=0/flow=$STUDENT-acl-icmp-h3/opendaylight-flow-statistics:flow-statistics?content=nonconfig"
docker exec clab-$STUDENT-l4-s1 ovs-ofctl -O OpenFlow13 dump-flows br0 | grep drop
del_flow 1 $STUDENT-acl-icmp-h3
sleep 1
docker exec clab-$STUDENT-l4-h1 ping -c 2 10.$N.4.3
```

Видно: `priority=507,icmp,in_port=1,nw_dst=10.7.4.3 actions=drop` с `n_packets=2, n_bytes=196`; после трёх ping в REST `"packet-count": "5"`, `"byte-count": "490"` и то же в OVS; `DELETE … 204`; ping h3 снова проходит.

## Скрин 8. Этап 5.1: контроллер выключен, режим secure

Блок выполняется около 25 секунд.

```bash
docker stop clab-$STUDENT-l4-odl
sleep 20
docker exec clab-$STUDENT-l4-s1 ovs-vsctl show | grep -A1 Controller
docker exec clab-$STUDENT-l4-h1 ping -c 3 10.$N.4.2
docker exec clab-$STUDENT-l4-h2 ping -c 2 -W 1 10.$N.4.3
docker exec clab-$STUDENT-l4-s2 ovs-ofctl -O OpenFlow13 dump-flows br0
```

Видно: под `Controller` больше нет `is_connected: true`; h1 → h2 `0% packet loss`; h2 → h3 `100% packet loss`; все потоки на s2 на месте.

## Скрин 9. Этап 5.2: режим standalone

Блок выполняется около 35 секунд.

```bash
docker exec clab-$STUDENT-l4-s1 ovs-vsctl set-fail-mode br0 standalone
docker exec clab-$STUDENT-l4-s2 ovs-vsctl set-fail-mode br0 standalone
sleep 30
docker exec clab-$STUDENT-l4-s2 ovs-ofctl -O OpenFlow13 dump-flows br0
docker exec clab-$STUDENT-l4-s2 ovs-appctl bridge/dump-flows br0 | grep -v table_id=254
docker exec clab-$STUDENT-l4-s2 grep "failing open" /var/log/openvswitch/ovs-vswitchd.log | tail -1
docker exec clab-$STUDENT-l4-h2 ping -c 3 10.$N.4.3
```

Видно: `dump-flows` пустой, скрытый поток `priority=15790320,actions=NORMAL`, в логе `… failing open`, h2 → h3 `0% packet loss`.

## Скрин 10. Этап 5.3: возврат контроллера

Блок выполняется около 65 секунд.

```bash
docker exec clab-$STUDENT-l4-s1 ovs-vsctl set-fail-mode br0 secure
docker exec clab-$STUDENT-l4-s2 ovs-vsctl set-fail-mode br0 secure
docker exec clab-$STUDENT-l4-h1 ping -c 2 -W 1 10.$N.4.2 | tail -2
docker start clab-$STUDENT-l4-odl && sleep 60
docker exec clab-$STUDENT-l4-s2 ovs-vsctl show | grep -A1 Controller
docker exec clab-$STUDENT-l4-s2 ovs-ofctl -O OpenFlow13 dump-flows br0
```

Видно: до старта ODL ping `100% packet loss` (secure + пустая таблица); после старта `is_connected: true`, шесть потоков `yakovlev` и table-miss на s2 со счётчиками около нуля.

## Скрин 11. Финальный артефакт

Первые две строки прогоняют трафик: после reconciliation счётчики обнулены, а на скрине нужны ненулевые `n_packets`.

```bash
docker exec clab-$STUDENT-l4-h1 ping -c 3 -q 10.$N.4.2 >/dev/null
docker exec clab-$STUDENT-l4-h1 ping -c 3 -q 10.$N.4.3 >/dev/null
echo "========================================" && \
echo "ЛР4 завершена: $(date '+%d.%m.%Y %H:%M:%S')" && \
echo "Студент: $(whoami)@$(hostname), STUDENT=$STUDENT, N=$N" && \
echo "========================================" && \
docker exec clab-$STUDENT-l4-s2 ovs-vsctl show | grep -E "Bridge|Controller|is_connected|fail_mode" && \
odl_get "opendaylight-inventory:nodes?content=nonconfig&depth=3" | jq -c '[."opendaylight-inventory:nodes".node[].id]' && \
docker exec clab-$STUDENT-l4-s2 ovs-ofctl -O OpenFlow13 dump-flows br0 && \
docker exec clab-$STUDENT-l4-h1 ping -c 2 10.$N.4.3
```

Видно все пять пунктов из задания: `is_connected: true` и `fail_mode: secure`, `["openflow:1","openflow:2"]`, потоки с `10.7.4.x` и ненулевыми `n_packets`, ping h1 → h3, логин, хост и время.

---

## Для PDF без скриншотов

JSON-файлы потоков (раздел 4 PDF) — текстом:

```bash
for f in flows/*.json; do echo "== $f"; jq -c . "$f"; done
```

Схема — в [README.md](README.md), раздел «Схема». Ответы на вопросы — в [README.md](README.md) и [DEFENSE.md](DEFENSE.md).

## После защиты

```bash
containerlab destroy -t lab4.clab.yml --cleanup
```
