__DATA__
  - platform: mqtt
    name: "xiaomi_AABB_temperature"
    unique_id: "xiaomi_AABB_temperature"
    state_topic: "/custom/xiaomi_AABB"
    device_class: temperature         # https://www.home-assistant.io/integrations/sensor/#device-class
    unit_of_measurement: "°C"
    # expire_after: 600                 # Defines the number of seconds after the value expires if it’s not updated.
    force_update: true                # Sends update events even if the value hasn’t changed. Useful if you want to have meaningful value graphs in history.
    value_template: "{{ value_json.temperature }}"
  - platform: mqtt
    name: "xiaomi_AABB_moisture"
    unique_id: "xiaomi_AABB_moisture"
    state_topic: "/custom/xiaomi_AABB"
    device_class: humidity # https://www.home-assistant.io/integrations/sensor/#device-class
    unit_of_measurement: "%"
    # expire_after: 600                 # Defines the number of seconds after the value expires if it’s not updated.
    force_update: true                # Sends update events even if the value hasn’t changed. Useful if you want to have meaningful value graphs in history.
    value_template: "{{ value_json.moisture}}"
  - platform: mqtt
    name: "xiaomi_AABB_light"
    unique_id: "xiaomi_AABB_light"
    state_topic: "/custom/xiaomi_AABB"
    device_class: illuminance # https://www.home-assistant.io/integrations/sensor/#device-class
    unit_of_measurement: "lux"
    # expire_after: 600                 # Defines the number of seconds after the value expires if it’s not updated.
    force_update: true                # Sends update events even if the value hasn’t changed. Useful if you want to have meaningful value graphs in history.
    value_template: "{{ value_json.light}}"
  - platform: mqtt
    name: "xiaomi_AABB_fertility"
    unique_id: "xiaomi_AABB_fertility"
    state_topic: "/custom/xiaomi_AABB"
    # device_class: illuminance # https://www.home-assistant.io/integrations/sensor/#device-class
    unit_of_measurement: "µS/cm"
    # expire_after: 600                 # Defines the number of seconds after the value expires if it’s not updated.
    force_update: true                # Sends update events even if the value hasn’t changed. Useful if you want to have meaningful value graphs in history.
    value_template: "{{ value_json.fertility}}"
  - platform: mqtt
    name: "xiaomi_AABB_battery"
    unique_id: "xiaomi_AABB_battery"
    state_topic: "/custom/xiaomi_AABB"
    device_class: battery # https://www.home-assistant.io/integrations/sensor/#device-class
    unit_of_measurement: "%"
    # expire_after: 600                 # Defines the number of seconds after the value expires if it’s not updated.
    force_update: true                # Sends update events even if the value hasn’t changed. Useful if you want to have meaningful value graphs in history.
    value_template: "{{ value_json.battery}}"
