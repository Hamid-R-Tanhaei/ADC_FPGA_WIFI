/*
 * ESP32 data monitoring program
 * setup Wifi as Access-Point
 * Author : Hamid_Reza_Tanhaei
 * */
#include <stdio.h>
#include "sdkconfig.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "esp_system.h"
#include "esp_spi_flash.h"
#include "driver/gpio.h"

#include "esp_wifi.h"
#include "esp_event.h"
#include "esp_log.h"
#include "nvs_flash.h"

#include "esp_netif.h"
//#include "protocol_examples_common.h"

#include "lwip/err.h"
#include "lwip/sys.h"
#include "lwip/sockets.h"
#include <lwip/netdb.h>


#ifdef CONFIG_IDF_TARGET_ESP32
#define CHIP_NAME "ESP32"
#endif

#ifdef CONFIG_IDF_TARGET_ESP32S2BETA
#define CHIP_NAME "ESP32-S2 Beta"
#endif
/////////////
//control IOs:
#define ESP_RDY 33 //OUT
#define ESP_SYNC 25 //OUT
// Data input:
#define ESP_DAT0 	23
#define ESP_DAT1 	22
#define ESP_DAT2 	26
#define ESP_DAT3 	27
#define ESP_DAT4 	14
#define ESP_DAT5 	13
#define ESP_DAT6 	21
#define ESP_DAT7 	4

/////////////////
#define EXAMPLE_ESP_WIFI_SSID      "ESP32_AP"
#define EXAMPLE_ESP_WIFI_PASS      "Hamid_esp32"
#define EXAMPLE_ESP_WIFI_CHANNEL   1
#define EXAMPLE_MAX_STA_CONN       1

static const char *TAG = "wifi softAP";
#define PORT 3333

#define	CONFIG_EXAMPLE_IPV4 1
static const char *TAG2 = "TCP_server";

///////////////////////////////////////////////////////
void initiaize_gpios(){
	printf("\nInitialize GPIOs\n");

	gpio_pad_select_gpio(ESP_SYNC);
	gpio_pad_select_gpio(ESP_RDY);
	gpio_pad_select_gpio(ESP_DAT0);
	gpio_pad_select_gpio(ESP_DAT1);
	gpio_pad_select_gpio(ESP_DAT2);
	gpio_pad_select_gpio(ESP_DAT3);
	gpio_pad_select_gpio(ESP_DAT4);
	gpio_pad_select_gpio(ESP_DAT5);
	gpio_pad_select_gpio(ESP_DAT6);
	gpio_pad_select_gpio(ESP_DAT7);

	gpio_set_direction(ESP_SYNC, GPIO_MODE_OUTPUT);
	gpio_set_direction(ESP_RDY, GPIO_MODE_OUTPUT);
	//
	gpio_set_direction(ESP_DAT0, GPIO_MODE_INPUT);
	gpio_set_direction(ESP_DAT1, GPIO_MODE_INPUT);
	gpio_set_direction(ESP_DAT2, GPIO_MODE_INPUT);
	gpio_set_direction(ESP_DAT3, GPIO_MODE_INPUT);
	gpio_set_direction(ESP_DAT4, GPIO_MODE_INPUT);
	gpio_set_direction(ESP_DAT5, GPIO_MODE_INPUT);
	gpio_set_direction(ESP_DAT6, GPIO_MODE_INPUT);
	gpio_set_direction(ESP_DAT7, GPIO_MODE_INPUT);
	//
    gpio_set_level(ESP_RDY, 0);
    gpio_set_level(ESP_SYNC, 0);

}
////////////////////////////////////////////////
void fpga_interaction(uint8_t * tx_buffer, int tx_size, uint8_t * rx_buffer, int rx_size){
	u8_t in_valueL; // in_valueH;
	u8_t base;
	int del;
    gpio_set_level(ESP_SYNC,0);
    gpio_set_level(ESP_RDY, 1);
    for (int idx = 0; idx < tx_size; idx++){
				for (del = 0; del < 4; del++){}
	    gpio_set_level(ESP_SYNC,1); // rising edge
	    in_valueL = 0;
	    base = 0b00000001;
		//
	    if (gpio_get_level(ESP_DAT0))
	    	in_valueL |= base;
	    if (gpio_get_level(ESP_DAT1))
	    	in_valueL |= (base << 1);
	    if (gpio_get_level(ESP_DAT2))
	    	in_valueL |= (base << 2);
	    if (gpio_get_level(ESP_DAT3))
	    	in_valueL |= (base << 3);
	    if (gpio_get_level(ESP_DAT4))
	    	in_valueL |= (base << 4);
	    if (gpio_get_level(ESP_DAT5))
	    	in_valueL |= (base << 5);
	    if (gpio_get_level(ESP_DAT6))
	    	in_valueL |= (base << 6);
	    if (gpio_get_level(ESP_DAT7))
	    	in_valueL |= (base << 7);
	    //
	    gpio_set_level(ESP_SYNC,0);
	    tx_buffer[idx]    = in_valueL;
	}
    gpio_set_level(ESP_RDY, 0);
}
/////////////////////////////////////////
static void do_retransmit(const int sock)
{
    int len;
    uint8_t rx_buffer[16];
    uint8_t tx_buffer[1024];
    int to_write;
    int written;
    int buffer_indx;
    int recv_bytes = 0;
    int sent_bytes = 0;
    while(1) {
        len = recv(sock, rx_buffer, 16, 0);
        if (len < 1)
        	break;
        recv_bytes += len;
        fpga_interaction(tx_buffer, sizeof(tx_buffer), rx_buffer, sizeof(rx_buffer));
            to_write = sizeof(tx_buffer);
            written = 0;
            sent_bytes = 0;
            while (to_write > 0) {
            	buffer_indx = written;
                written = send(sock, tx_buffer + buffer_indx, to_write, 0);
                if (written < 0){
                	break;
                }
                sent_bytes += written;
                to_write -= written;
            }
    } //while (len > 0);
    ESP_LOGI(TAG2, "Received %d bytes", recv_bytes);
	ESP_LOGI(TAG2, "Sending %d bytes", sent_bytes);
}
/////////////////////////////
static void tcp_server_task(void *pvParameters)
//void tcp_server_task(void)
{
    char addr_str[128];
    int addr_family;
    int ip_protocol;


#ifdef CONFIG_EXAMPLE_IPV4
    struct sockaddr_in dest_addr;
    dest_addr.sin_addr.s_addr = htonl(INADDR_ANY);
    dest_addr.sin_family = AF_INET;
    dest_addr.sin_port = htons(PORT);
    addr_family = AF_INET;
    ip_protocol = IPPROTO_IP;
    inet_ntoa_r(dest_addr.sin_addr, addr_str, sizeof(addr_str) - 1);
#else // IPV6
    struct sockaddr_in6 dest_addr;
    bzero(&dest_addr.sin6_addr.un, sizeof(dest_addr.sin6_addr.un));
    dest_addr.sin6_family = AF_INET6;
    dest_addr.sin6_port = htons(PORT);
    addr_family = AF_INET6;
    ip_protocol = IPPROTO_IPV6;
    inet6_ntoa_r(dest_addr.sin6_addr, addr_str, sizeof(addr_str) - 1);
#endif

    int listen_sock = socket(addr_family, SOCK_STREAM, ip_protocol);
    if (listen_sock < 0) {
        ESP_LOGE(TAG2, "Unable to create socket: errno %d", errno);
        vTaskDelete(NULL);
        return;
    }
    ESP_LOGI(TAG2, "Socket created");

    int err = bind(listen_sock, (struct sockaddr *)&dest_addr, sizeof(dest_addr));
    if (err != 0) {
        ESP_LOGE(TAG2, "Socket unable to bind: errno %d", errno);
        goto CLEAN_UP;
    }
    ESP_LOGI(TAG2, "Socket bound, port %d", PORT);

    err = listen(listen_sock, 1);
    if (err != 0) {
        ESP_LOGE(TAG2, "Error occurred during listen: errno %d", errno);
        goto CLEAN_UP;
    }

    while (1) {

        ESP_LOGI(TAG2, "Socket listening");

        struct sockaddr_in6 source_addr; // Large enough for both IPv4 or IPv6
        uint addr_len = sizeof(source_addr);
        int sock = accept(listen_sock, (struct sockaddr *)&source_addr, &addr_len);
        if (sock < 0) {
            ESP_LOGE(TAG2, "Unable to accept connection: errno %d", errno);
            break;
        }

        // Convert ip address to string
        if (source_addr.sin6_family == PF_INET) {
            inet_ntoa_r(((struct sockaddr_in *)&source_addr)->sin_addr.s_addr, addr_str, sizeof(addr_str) - 1);
        } else if (source_addr.sin6_family == PF_INET6) {
            inet6_ntoa_r(source_addr.sin6_addr, addr_str, sizeof(addr_str) - 1);
        }
        ESP_LOGI(TAG2, "Socket accepted ip address: %s", addr_str);

        do_retransmit(sock);

        shutdown(sock, 0);
        ESP_LOGI(TAG2, "Socket shutdown.");
        close(sock);
        ESP_LOGI(TAG2, "Socket closed.");
    }

CLEAN_UP:
    close(listen_sock);
    vTaskDelete(NULL);
}
////////////////////////////////////////////////////////////
static void wifi_event_handler(void* arg, esp_event_base_t event_base,
                                    int32_t event_id, void* event_data)
{
    if (event_id == WIFI_EVENT_AP_STACONNECTED) {
        wifi_event_ap_staconnected_t* event = (wifi_event_ap_staconnected_t*) event_data;
        ESP_LOGI(TAG, "station "MACSTR" join, AID=%d",
                 MAC2STR(event->mac), event->aid);
    } else if (event_id == WIFI_EVENT_AP_STADISCONNECTED) {
        wifi_event_ap_stadisconnected_t* event = (wifi_event_ap_stadisconnected_t*) event_data;
        ESP_LOGI(TAG, "station "MACSTR" leave, AID=%d",
                 MAC2STR(event->mac), event->aid);
    }
}

///////////
void wifi_init_softap(void)
{
    ESP_ERROR_CHECK(esp_netif_init());
    ESP_ERROR_CHECK(esp_event_loop_create_default());
    esp_netif_create_default_wifi_ap();

    wifi_init_config_t cfg = WIFI_INIT_CONFIG_DEFAULT();
    ESP_ERROR_CHECK(esp_wifi_init(&cfg));

    ESP_ERROR_CHECK(esp_event_handler_register(WIFI_EVENT, ESP_EVENT_ANY_ID, &wifi_event_handler, NULL));

    wifi_config_t wifi_config = {
        .ap = {
            .ssid = EXAMPLE_ESP_WIFI_SSID,
            .ssid_len = strlen(EXAMPLE_ESP_WIFI_SSID),
            .channel = EXAMPLE_ESP_WIFI_CHANNEL,
            .password = EXAMPLE_ESP_WIFI_PASS,
            .max_connection = EXAMPLE_MAX_STA_CONN,
            .authmode = WIFI_AUTH_WPA_WPA2_PSK
        },
    };
    if (strlen(EXAMPLE_ESP_WIFI_PASS) == 0) {
        wifi_config.ap.authmode = WIFI_AUTH_OPEN;
    }

    ESP_ERROR_CHECK(esp_wifi_set_mode(WIFI_MODE_AP));
    ESP_ERROR_CHECK(esp_wifi_set_config(ESP_IF_WIFI_AP, &wifi_config));
    ESP_ERROR_CHECK(esp_wifi_start());

    ESP_LOGI(TAG, "wifi_init_softap finished. SSID:%s password:%s channel:%d",
             EXAMPLE_ESP_WIFI_SSID, EXAMPLE_ESP_WIFI_PASS, EXAMPLE_ESP_WIFI_CHANNEL);
    printf("wifi_init_softap finished. SSID:%s password:%s channel:%d",
             EXAMPLE_ESP_WIFI_SSID, EXAMPLE_ESP_WIFI_PASS, EXAMPLE_ESP_WIFI_CHANNEL);
}



////////////
void app_main(void)
{
    printf("Hello world!\n");

    /* Print chip information */
    esp_chip_info_t chip_info;
    esp_chip_info(&chip_info);
    printf("This is %s chip with %d CPU cores, WiFi%s%s, ",
            CHIP_NAME,
            chip_info.cores,
            (chip_info.features & CHIP_FEATURE_BT) ? "/BT" : "",
            (chip_info.features & CHIP_FEATURE_BLE) ? "/BLE" : "");

    printf("silicon revision %d, ", chip_info.revision);

    printf("%dMB %s flash\n", spi_flash_get_chip_size() / (1024 * 1024),
            (chip_info.features & CHIP_FEATURE_EMB_FLASH) ? "embedded" : "external");
    ///////////////////////////////////////
    //Initialize NVS
    esp_err_t ret = nvs_flash_init();
    if (ret == ESP_ERR_NVS_NO_FREE_PAGES || ret == ESP_ERR_NVS_NEW_VERSION_FOUND) {
      ESP_ERROR_CHECK(nvs_flash_erase());
      ret = nvs_flash_init();
    }
    ESP_ERROR_CHECK(ret);

    ESP_LOGI(TAG, "ESP_WIFI_MODE_AP");
    //
    initiaize_gpios();
    //
    wifi_init_softap();
    //xTaskCreate(tcp_server_task, "tcp_server", 4096, NULL, 5, NULL);
    xTaskCreate(tcp_server_task, "tcp_server", 8192, NULL, 5, NULL);
    initiaize_gpios();

    while(1){
        vTaskDelay(1000 / portTICK_PERIOD_MS);
    }

    printf("Restarting now.\n");
    fflush(stdout);
    esp_restart();
}
