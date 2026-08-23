/*
 * Wi-Fi CSI Router MVP for classic ESP32 / ESP-WROOM-32
 *
 * Target framework: ESP-IDF v6.0.x
 *
 * Flow:
 *   ESP32 STA -> ICMP Echo Request -> router/default gateway
 *   router -> ICMP Echo Reply -> ESP32 CSI callback
 *   callback -> FreeRTOS queue -> UART CSV output
 *
 * The CSI configuration intentionally uses LLTF only. This mirrors the
 * compatibility-oriented path used by Espressif's csi_recv_router example
 * for the original ESP32 family and provides a stable first experiment.
 */

#include <stdbool.h>
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "freertos/FreeRTOS.h"
#include "freertos/event_groups.h"
#include "freertos/queue.h"
#include "freertos/task.h"

#include "driver/uart.h"
#include "esp_event.h"
#include "esp_log.h"
#include "esp_mac.h"
#include "esp_netif.h"
#include "esp_wifi.h"
#include "nvs_flash.h"

#include "lwip/ip_addr.h"
#include "ping/ping_sock.h"

#define WIFI_CONNECTED_BIT BIT0
#define CSI_MAX_DATA_LEN 256
#define CSI_LINE_BUFFER_SIZE 3072
#define CSI_UART_BAUD_RATE 921600

static const char *TAG = "csi_router_mvp";

static EventGroupHandle_t s_wifi_event_group;
static QueueHandle_t s_csi_queue;
static esp_netif_t *s_sta_netif;
static uint8_t s_ap_bssid[6];
static volatile uint32_t s_sequence;
static volatile uint32_t s_dropped_frames;

typedef struct {
    uint32_t seq;
    uint8_t mac[6];
    int8_t rssi;
    uint8_t rate;
    int8_t noise_floor;
    uint8_t channel;
    uint32_t timestamp;
    uint16_t sig_len;
    uint8_t rx_format;
    uint16_t len;
    bool first_word_invalid;
    int8_t data[CSI_MAX_DATA_LEN];
} csi_frame_t;

static void wifi_event_handler(
    void *arg,
    esp_event_base_t event_base,
    int32_t event_id,
    void *event_data)
{
    (void)arg;
    (void)event_data;

    if (event_base == WIFI_EVENT && event_id == WIFI_EVENT_STA_START) {
        ESP_ERROR_CHECK(esp_wifi_connect());
        return;
    }

    if (event_base == WIFI_EVENT && event_id == WIFI_EVENT_STA_DISCONNECTED) {
        xEventGroupClearBits(s_wifi_event_group, WIFI_CONNECTED_BIT);
        ESP_LOGW(TAG, "Wi-Fi disconnected; reconnecting");
        esp_wifi_connect();
        return;
    }

    if (event_base == IP_EVENT && event_id == IP_EVENT_STA_GOT_IP) {
        xEventGroupSetBits(s_wifi_event_group, WIFI_CONNECTED_BIT);
    }
}

static void wifi_init_sta(void)
{
    if (strlen(CONFIG_CSI_WIFI_SSID) == 0) {
        printf("#ERROR,Wi-Fi SSID is empty. Run idf.py menuconfig first.\n");
        abort();
    }

    s_wifi_event_group = xEventGroupCreate();
    if (s_wifi_event_group == NULL) {
        abort();
    }

    s_sta_netif = esp_netif_create_default_wifi_sta();
    if (s_sta_netif == NULL) {
        abort();
    }

    wifi_init_config_t init_config = WIFI_INIT_CONFIG_DEFAULT();
    ESP_ERROR_CHECK(esp_wifi_init(&init_config));

    ESP_ERROR_CHECK(esp_event_handler_register(
        WIFI_EVENT, ESP_EVENT_ANY_ID, &wifi_event_handler, NULL));
    ESP_ERROR_CHECK(esp_event_handler_register(
        IP_EVENT, IP_EVENT_STA_GOT_IP, &wifi_event_handler, NULL));

    wifi_config_t wifi_config = {0};
    snprintf((char *)wifi_config.sta.ssid,
             sizeof(wifi_config.sta.ssid),
             "%s",
             CONFIG_CSI_WIFI_SSID);
    snprintf((char *)wifi_config.sta.password,
             sizeof(wifi_config.sta.password),
             "%s",
             CONFIG_CSI_WIFI_PASSWORD);
    wifi_config.sta.failure_retry_cnt = 10;

    ESP_ERROR_CHECK(esp_wifi_set_mode(WIFI_MODE_STA));
    ESP_ERROR_CHECK(esp_wifi_set_config(WIFI_IF_STA, &wifi_config));
    ESP_ERROR_CHECK(esp_wifi_start());
    ESP_ERROR_CHECK(esp_wifi_set_ps(WIFI_PS_NONE));

    printf("#STATUS,connecting,ssid=%s\n", CONFIG_CSI_WIFI_SSID);
    xEventGroupWaitBits(
        s_wifi_event_group,
        WIFI_CONNECTED_BIT,
        pdFALSE,
        pdTRUE,
        portMAX_DELAY);

    wifi_ap_record_t ap_info = {0};
    ESP_ERROR_CHECK(esp_wifi_sta_get_ap_info(&ap_info));
    memcpy(s_ap_bssid, ap_info.bssid, sizeof(s_ap_bssid));

    printf("#STATUS,connected,bssid=" MACSTR ",channel=%u,rssi=%d\n",
           MAC2STR(s_ap_bssid), ap_info.primary, ap_info.rssi);
}

static void wifi_csi_rx_callback(void *ctx, wifi_csi_info_t *info)
{
    (void)ctx;

    if (info == NULL || info->buf == NULL || info->len < 2) {
        return;
    }

    /* Keep only frames transmitted by the AP we are associated with. */
    if (memcmp(info->mac, s_ap_bssid, sizeof(s_ap_bssid)) != 0) {
        return;
    }

    csi_frame_t frame = {0};
    const wifi_pkt_rx_ctrl_t *rx = &info->rx_ctrl;

    frame.seq = s_sequence++;
    memcpy(frame.mac, info->mac, sizeof(frame.mac));
    frame.rssi = rx->rssi;
    frame.rate = rx->rate;
    frame.noise_floor = rx->noise_floor;
    frame.channel = rx->channel;
    frame.timestamp = rx->timestamp;
    frame.sig_len = rx->sig_len;
    /* On the original ESP32, sig_mode is the useful PHY-format indicator. */
    frame.rx_format = rx->sig_mode;
    frame.len = info->len > CSI_MAX_DATA_LEN ? CSI_MAX_DATA_LEN : info->len;
    frame.first_word_invalid = info->first_word_invalid;
    memcpy(frame.data, info->buf, frame.len);

    if (xQueueSend(s_csi_queue, &frame, 0) != pdTRUE) {
        s_dropped_frames++;
    }
}

static void csi_print_task(void *arg)
{
    (void)arg;
    csi_frame_t frame;
    char line[CSI_LINE_BUFFER_SIZE];
    uint32_t last_stats_ms = 0;

    setvbuf(stdout, NULL, _IONBF, 0);

    printf("type,seq,mac,rssi,rate,noise_floor,channel,local_timestamp,"
           "sig_len,rx_format,len,first_word,data\n");

    while (true) {
        if (xQueueReceive(s_csi_queue, &frame, portMAX_DELAY) != pdTRUE) {
            continue;
        }

        int written = snprintf(
            line,
            sizeof(line),
            "CSI_DATA,%" PRIu32 "," MACSTR ",%d,%u,%d,%u,%" PRIu32
            ",%u,%u,%u,%u,\"[",
            frame.seq,
            MAC2STR(frame.mac),
            frame.rssi,
            frame.rate,
            frame.noise_floor,
            frame.channel,
            frame.timestamp,
            frame.sig_len,
            frame.rx_format,
            frame.len,
            frame.first_word_invalid ? 1U : 0U);

        if (written < 0 || (size_t)written >= sizeof(line)) {
            s_dropped_frames++;
            continue;
        }

        size_t offset = (size_t)written;
        bool truncated = false;
        for (uint16_t i = 0; i < frame.len; ++i) {
            int n = snprintf(
                line + offset,
                sizeof(line) - offset,
                i == 0 ? "%d" : ",%d",
                frame.data[i]);

            if (n < 0 || (size_t)n >= sizeof(line) - offset) {
                truncated = true;
                break;
            }
            offset += (size_t)n;
        }

        if (truncated || offset + 4 >= sizeof(line)) {
            s_dropped_frames++;
            continue;
        }

        line[offset++] = ']';
        line[offset++] = '"';
        line[offset++] = '\n';
        line[offset] = '\0';
        fwrite(line, 1, offset, stdout);

        const uint32_t now_ms = frame.timestamp / 1000U;
        if (now_ms - last_stats_ms >= 5000U) {
            last_stats_ms = now_ms;
            fprintf(stderr,
                    "#STATS,seq=%" PRIu32 ",dropped=%" PRIu32
                    ",queue=%u\n",
                    frame.seq,
                    s_dropped_frames,
                    (unsigned int)uxQueueMessagesWaiting(s_csi_queue));
        }
    }
}

static void wifi_csi_start(void)
{
    /*
     * Classic ESP32 CSI configuration. LLTF-only is intentionally selected
     * for broad router compatibility, matching Espressif's router example.
     */
    wifi_csi_config_t csi_config = {
        .lltf_en = true,
        .htltf_en = false,
        .stbc_htltf2_en = false,
        .ltf_merge_en = true,
        .channel_filter_en = true,
        .manu_scale = true,
        .shift = true,
    };

    ESP_ERROR_CHECK(esp_wifi_set_csi_config(&csi_config));
    ESP_ERROR_CHECK(esp_wifi_set_csi_rx_cb(wifi_csi_rx_callback, NULL));
    ESP_ERROR_CHECK(esp_wifi_set_csi(true));
    printf("#STATUS,csi_enabled,mode=LLTF\n");
}

static void router_ping_start(void)
{
    esp_netif_ip_info_t ip_info = {0};
    ESP_ERROR_CHECK(esp_netif_get_ip_info(s_sta_netif, &ip_info));

    esp_ping_config_t ping_config = ESP_PING_DEFAULT_CONFIG();
    ping_config.count = 0;
    ping_config.interval_ms = 1000U / CONFIG_CSI_PING_RATE_HZ;
    if (ping_config.interval_ms == 0) {
        ping_config.interval_ms = 1;
    }
    ping_config.task_stack_size = 3072;
    ping_config.data_size = 1;
    ping_config.target_addr.u_addr.ip4.addr = ip_info.gw.addr;
    ping_config.target_addr.type = ESP_IPADDR_TYPE_V4;

    esp_ping_callbacks_t callbacks = {0};
    esp_ping_handle_t ping_handle = NULL;
    ESP_ERROR_CHECK(esp_ping_new_session(&ping_config, &callbacks, &ping_handle));
    ESP_ERROR_CHECK(esp_ping_start(ping_handle));

    printf("#STATUS,ping_started,rate_hz=%d\n", CONFIG_CSI_PING_RATE_HZ);
}

void app_main(void)
{
    ESP_ERROR_CHECK(uart_set_baudrate(UART_NUM_0, CSI_UART_BAUD_RATE));

    esp_err_t nvs_result = nvs_flash_init();
    if (nvs_result == ESP_ERR_NVS_NO_FREE_PAGES ||
        nvs_result == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        ESP_ERROR_CHECK(nvs_flash_erase());
        nvs_result = nvs_flash_init();
    }
    ESP_ERROR_CHECK(nvs_result);
    ESP_ERROR_CHECK(esp_netif_init());
    ESP_ERROR_CHECK(esp_event_loop_create_default());

    s_csi_queue = xQueueCreate(CONFIG_CSI_QUEUE_LENGTH, sizeof(csi_frame_t));
    if (s_csi_queue == NULL) {
        abort();
    }

    wifi_init_sta();

    BaseType_t task_result = xTaskCreate(
        csi_print_task,
        "csi_print",
        8192,
        NULL,
        5,
        NULL);
    if (task_result != pdPASS) {
        abort();
    }

    wifi_csi_start();
    router_ping_start();
}
