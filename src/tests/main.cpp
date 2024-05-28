#include <cassert>
#include <XController.h>
#include <stdio.h>

namespace ChannelGroup_Tests {
    void Helper_PrintPacketEncoderRequest(MaIPCPacket &packet) {
        assert(packet.type == IPCMessageType::UPDATE_ENCODER_WATCHLIST);
        
        for(int i = 0; i < PHYSICAL_CHANNEL_COUNT; i++) {
            auto channel_data = &packet.EncoderRequest[i];
            printf("[%u] Channel=%u, Page=%u\n", i, channel_data->channel, channel_data->page);
        }
        printf("\n");
    }

    void InitialState() {
        printf("-> Running ChannelGroup_Tests::InitialState\n");
        ChannelGroup group;
        assert(group.m_page == 1);
        assert(group.m_channelOffset == 0);
    }
    void ChangePage() {
        printf("-> Running ChannelGroup_Tests::ChangePage\n");
        ChannelGroup group;
        uint32_t activePage = 1;
        group.RegisterMAOutCB([&](MaIPCPacket &packet) {
            assert(packet.type == IPCMessageType::UPDATE_ENCODER_WATCHLIST);
            for(int i = 0; i < PHYSICAL_CHANNEL_COUNT; i++) {
                auto channel_data = &packet.EncoderRequest[i];
                assert(channel_data->channel == i + 1);
                assert(channel_data->page == activePage);
            }
        });
        assert(group.m_page == 1);

        activePage += 1; // Page 2
        group.ChangePage(1);

        activePage += -1; // Page 1
        group.ChangePage(-1);

        // Should stay page 1
        group.ChangePage(-1);
    }
    void ChangeChannelOffset() {
        printf("-> Running ChannelGroup_Tests::ChangeChannelOffset\n");
        ChannelGroup group;
        uint32_t channelOffset = 1;
        group.RegisterMAOutCB([&](MaIPCPacket &packet) {
            assert(packet.type == IPCMessageType::UPDATE_ENCODER_WATCHLIST);
            for(int i = 0; i < PHYSICAL_CHANNEL_COUNT; i++) {
                auto channel_data = &packet.EncoderRequest[i];
                assert((channel_data->channel - channelOffset) == i); 
                assert(channel_data->page == 1);
            }
        });
        assert(group.m_page == 1);
    }
    void CheckUpdatePinConfigExitButtonLogic() {
        printf("-> Running ChannelGroup_Tests::CheckUpdatePinButtonLogic\n");
        ChannelGroup group;

        // Check our logic for exiting PIN mode
        for(int i = 0; i < xt_buttons::END; i++) {
            auto btn = static_cast<xt_buttons>(i);
            if (btn >= FADER_0_SELECT && btn <= FADER_7_SELECT) { continue; }
            if (btn >= FADER_0_MUTE && btn <= FADER_7_MUTE) { continue; }

            // Enter pin config mode
            group.UpdatePinnedChannels(static_cast<xt_buttons>(xt_alias_btn::PIN));
            assert(group.m_pinConfigMode);

            // Didn't hit MUTE (for pinned channel), nor SELECT, so we should exit config mode
            group.UpdatePinnedChannels(btn);
            if (group.m_pinConfigMode) {
                printf("btn: %u\n", btn);
                assert(false && "PIN mode was not disabled");
            }
        }

    }
    void CheckPinChangePageLog1() {
        printf("-> Running ChannelGroup_Tests::CheckPinChangePageLog1\n");
        ChannelGroup group;
        // Test pinning first channel. All other channels should be on page 2, from channel 1-7
        group.RegisterMAOutCB([&](MaIPCPacket &packet) {
            Helper_PrintPacketEncoderRequest(packet);
            auto ch_i = 1;
            for(int i = 0; i < PHYSICAL_CHANNEL_COUNT; i++) {
                auto channel_data = &packet.EncoderRequest[i];
                auto channel = channel_data->channel;
                auto page = channel_data->page;
                if (i == 0) { // Physical channel that was pinned
                    assert(page == 1); 
                    assert(channel == 1);
                    continue;
                } 
                if (i == 7) { // Last item in list
                    assert(page == 2); 
                    assert(channel == 7);
                    break;
                } 

                assert(page == 2);
                assert(channel == ch_i++);
            }
        });

        group.UpdatePinnedChannels(static_cast<xt_buttons>(xt_alias_btn::PIN));
        group.UpdatePinnedChannels(xt_buttons::FADER_0_SELECT);
        group.ChangePage(1);
    }
    void CheckPinChangePageLog2() {
        printf("-> Running ChannelGroup_Tests::CheckPinChangePageLog2\n");
        ChannelGroup group;
  
        // Test pinning first and last channel. All other channels should be on page 2, from channel 1-6
        group.RegisterMAOutCB([&](MaIPCPacket &packet) {
            auto ch_i = 1;
            for(int i = 0; i < PHYSICAL_CHANNEL_COUNT; i++) {
                auto channel_data = &packet.EncoderRequest[i];
                auto channel = channel_data->channel;
                auto page = channel_data->page;
                if (i == 0) { // Physical channel that was pinned
                    assert(page == 1); 
                    assert(channel == 1);
                    continue;
                } 
                if (i == 7) { // Last item in list
                    assert(page == 1); 
                    assert(channel == 8);
                    break;
                } 

                assert(page == 2);
                assert(channel == ch_i++);
            }
        });

        group.UpdatePinnedChannels(static_cast<xt_buttons>(xt_alias_btn::PIN));
        group.UpdatePinnedChannels(xt_buttons::FADER_0_SELECT);
        group.UpdatePinnedChannels(static_cast<xt_buttons>(xt_alias_btn::PIN));
        group.UpdatePinnedChannels(xt_buttons::FADER_7_SELECT);

        group.ChangePage(1);
    }
    void CheckPinChangePageLog3() {
        printf("-> Running ChannelGroup_Tests::CheckPinChangePageLog3\n");
        ChannelGroup group;
  
        // Test pinning first, middle, and last channel. All other channels should be on page 2, from channel 1-5
        group.RegisterMAOutCB([&](MaIPCPacket &packet) {
            auto ch_i = 1;
            for(int i = 0; i < PHYSICAL_CHANNEL_COUNT; i++) {
                auto channel_data = &packet.EncoderRequest[i];
                auto channel = channel_data->channel;
                auto page = channel_data->page;
                if (i == 0) { // Physical channel that was pinned
                    assert(page == 1); 
                    assert(channel == 1);
                    continue;
                } 
                if (i == 4) { // Last item in list
                    assert(page == 1); 
                    assert(channel == 5);
                    break;
                } 
                if (i == 7) { // Last item in list
                    assert(page == 1); 
                    assert(channel == 8);
                    break;
                } 

                assert(page == 2);
                assert(channel == ch_i++);
            }
        });
    }
    void CheckPinChangePageLog4() {
        printf("-> Running ChannelGroup_Tests::CheckPinChangePageLog4\n");
        ChannelGroup group;
  
        group.UpdatePinnedChannels(static_cast<xt_buttons>(xt_alias_btn::PIN));
        group.UpdatePinnedChannels(xt_buttons::FADER_0_SELECT);
        group.ChangePage(1);

        // Test pinning first channel on page 1, last channel on page 2. All other should be on page
        // 3, from 1-6
        group.RegisterMAOutCB([&](MaIPCPacket &packet) {
            auto ch_i = 1;
            for(int i = 0; i < PHYSICAL_CHANNEL_COUNT; i++) {
                auto channel_data = &packet.EncoderRequest[i];
                auto channel = channel_data->channel;
                auto page = channel_data->page;
                if (i == 0) { // Physical channel that was pinned
                    assert(page == 1); 
                    assert(channel == 1);
                    continue;
                } 
                if (i == 7) { // Last item in list
                    assert(page == 2); 
                    assert(channel == 7);
                    break;
                } 

                assert(page == 3);
                assert(channel == ch_i++);
            }
        });

        group.UpdatePinnedChannels(static_cast<xt_buttons>(xt_alias_btn::PIN));
        group.UpdatePinnedChannels(xt_buttons::FADER_7_SELECT);
        group.ChangePage(1);
    }
    void CheckPinScrollPage() {
        printf("-> Running ChannelGroup_Tests::CheckPinScrollPage\n");
        ChannelGroup group;
  
        group.UpdatePinnedChannels(static_cast<xt_buttons>(xt_alias_btn::PIN));
        group.UpdatePinnedChannels(xt_buttons::FADER_0_SELECT);

        // Test pinning first channel, then scroll right.
        // There will only be 7 channels available for reassignment,
        // so we expect physical channel 1 to stay on channel 1, then
        // physical channel 2 should be [(width * page_offset) + i]
        // where width = number of physical channels available for reassignment
        group.RegisterMAOutCB([&](MaIPCPacket &packet) {
            // Helper_PrintPacketEncoderRequest(packet);

            auto ch_i = 9; 
            for(int i = 0; i < PHYSICAL_CHANNEL_COUNT; i++) {
                auto channel_data = &packet.EncoderRequest[i];
                auto channel = channel_data->channel;
                auto page = channel_data->page;
                if (i == 0) { // Physical channel that was pinned
                    assert(page == 1); 
                    assert(channel == 1);
                    continue;
                } 

                assert(page == 1);
                assert(channel == ch_i++); 
            }
        });

        group.ScrollPage(1);
    }
    void CheckPinScrollAndChangePage() {
        printf("-> Running ChannelGroup_Tests::CheckPinScrollAndChangePage\n");
        ChannelGroup group;
  
        group.UpdatePinnedChannels(static_cast<xt_buttons>(xt_alias_btn::PIN));
        group.UpdatePinnedChannels(xt_buttons::FADER_0_SELECT);
        group.ChangePage(1);

        // Test pinning first channel, then scroll right.
        // There will only be 7 channels available for reassignment,
        // so we expect physical channel 1 to stay on channel 1, then
        // physical channel 2 should be [(width * page_offset) + i]
        // where width = number of physical channels available for reassignment
        group.RegisterMAOutCB([&](MaIPCPacket &packet) {
            auto ch_i = 9; 
            for(int i = 0; i < PHYSICAL_CHANNEL_COUNT; i++) {
                auto channel_data = &packet.EncoderRequest[i];
                auto channel = channel_data->channel;
                auto page = channel_data->page;
                if (i == 0) { // Physical channel that was pinned
                    assert(page == 1); 
                    assert(channel == 1);
                    continue;
                } 

                assert(page == 2);
                assert(channel == ch_i++); 
            }
        });

        group.ScrollPage(1);
    }
}

int main(int, char**) {
    printf("------------ Running ChannelGroup tests ------------ \n");
    ChannelGroup_Tests::InitialState();
    ChannelGroup_Tests::ChangePage();
    ChannelGroup_Tests::ChangeChannelOffset();
    ChannelGroup_Tests::CheckUpdatePinConfigExitButtonLogic();
    ChannelGroup_Tests::CheckPinChangePageLog1();
    ChannelGroup_Tests::CheckPinChangePageLog2();
    ChannelGroup_Tests::CheckPinChangePageLog3();
    ChannelGroup_Tests::CheckPinChangePageLog4();
    ChannelGroup_Tests::CheckPinScrollPage();
    ChannelGroup_Tests::CheckPinScrollAndChangePage();

    return 0;
}