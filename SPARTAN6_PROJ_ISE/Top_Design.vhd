----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 	Hamid Reza Tanhaei
-- 
-- Create Date:    13:29:59 01/18/2021 
-- Design Name: 
-- Module Name:    FPGA_ADC_WIFI - Behavioral 
-- Project Name: 
-- Target Devices: 
-- Tool versions: 
-- Description: 
--
-- Dependencies: 
--
-- Revision: 
-- Revision 0.01 - File Created
-- Additional Comments: 
--
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity Top_Design is
    Port ( 
			CLK_IN 		: in  	STD_LOGIC;

			Test_Rx_p	: out	std_logic;
			Test_Rx_n	: out	std_logic;
			
			AD_CLK_OUT	: out	std_logic;
			AD_CLK1		: in 	std_logic;
			AD_CLK2		: in 	std_logic;
			
			AD_PWDN		: out	std_logic;
			AD_MODE		: out	std_logic;
			AD_CNFG		: out	std_logic;
			
			AD_SEN		: out	std_logic;
			AD_SCLK		: out	std_logic;
			AD_SDO		: in	std_logic;
			AD_SDIO		: out	std_logic;
			
			AD_RST		: out	std_logic;
			AD_RXEN		: out	std_logic;
			AD_TXEN		: out	std_logic;
			AD_PGA		: out	std_logic_vector(5 downto 0);
			AD_ADIO		: inout	std_logic_vector(9 downto 0);
				
			ESP32_Data 	: out  	std_logic_vector(7 downto 0);
			ESP32_Ready : in  	STD_LOGIC;
			ESP32_clk 	: in  	STD_LOGIC
			);
end Top_Design;

architecture Behavioral of Top_Design is
	------------------------------------
	signal	RAM1_WAddr	: std_logic_vector(9 downto 0) := (others => '0');
	signal	RAM1_RAddr	: std_logic_vector(9 downto 0) := (others => '0');
	signal	RAM1_WData	: std_logic_vector(9 downto 0) 	:= (others => '0');
	signal	RAM1_RData	: std_logic_vector(9 downto 0) 	:= (others => '0');
	signal	RAM1_WE		: std_logic_vector(0 downto 0) 	:= "0";
	signal	Ram_Waddr_cntr, Ram_Raddr_cntr : unsigned(9 downto 0) := (others => '0');
	signal	Timer_cntr 	: unsigned(15 downto 0) := (others => '0');
	------------------------------------
	------------------------------------------------
	-- control/timing signals:
	signal	Scan_En		:	std_logic := '0';
	signal	test_sig_cntr	 : 	unsigned(3 downto 0) := (others => '0');
	signal	Test_sig_Rx		 :	std_logic := '0';
	signal	CLK_75M, CLK_150M, CLK_5M, CLK_37M	:	std_logic;
	signal	CLK_Pre_150M	 :	std_logic := '0';
	-- AD9865 signals:
	signal	AD_clk_synth	:	std_logic := '0';
	signal	AD_RST_cntr		: 	unsigned(24 downto 0) := (others => '0');
	constant 	ADRxGain	: 	unsigned(5 downto 0) := "100100";
	signal	AD_init 		: 	std_logic := '0';
	signal	AD_pwup 		: 	std_logic := '0';
	signal	AD_reset 		: 	std_logic := '0';
	signal	AD_res_flag		: 	std_logic := '0';
	signal	AD_Tx_En, AD_Rx_En : std_logic := '0';
	signal	AD_Rx_Dat		: 	std_logic_vector(9 downto 0) := (others => '0');
	signal	AD_Tx_Dat		: 	std_logic_vector(9 downto 0) := (others => '0');
	signal	AD_reg_idx		:	unsigned(3 downto 0) := (others => '0'); --integer range 0 to 20 := 0;
	signal	AD_SPI_reg 		: 	std_logic_vector(14 downto 0) := (others => '0');
	signal	AD_SPI_comp		: 	std_logic_vector(14 downto 0) := (others => '0');
	signal	AD_SPI_ReadBack	:	std_logic_vector(7 downto 0) := (others => '0');
	signal 	AD_SPI_cntr 	: 	unsigned(6 downto 0) := (others => '0');
	signal 	AD_SDIO_out 	: 	std_logic := '0';
	signal 	AD_SDIO_dir 	: 	std_logic := '0';
	signal 	AD_Readback_flag: 	std_logic := '0';	
	signal	AD_SPI_error	: std_logic := '0';
	-- AD spi register values:
	constant	NumOfRegs	:	unsigned(3 downto 0) := to_unsigned(6, 4);
	type 	Reg_array is array (0 to 15) of std_logic_vector(14 downto 0);
	constant 	AD_Registers	: Reg_array :=
			(	
				-- Addr: 0x00, bit7: 4WireSPI(1), bit6: LSB-first(0), bit5: SW_reset(0)
				"000000010000000",	 
				-- Addr: 0x04, bit5: DutyCycleEn, bit4: fADC_PLL, bit32: PLLDivN, bit10: PLLMultM
				"000010000010101",
				-- Addr: 0x0C, bit76:Intpolfactor(01), bit4:InvTxEn(0), bit32:(00), bit1:TxNegEdge(1), bit0:2'sComp(1) 
				"000110001000011",
				-- Addr: 0x0D, bit7:Aloop(0), bit6:Dloop(0), bit5:(0), bit4:InvRxEn(0), bit32:(00), bit1:RxNegEdge(1), bit0:2'sComp(1) 
				"000110100000001",
				-- Addr: 0x03, bit7~3:TxOffDelay(11111), bit2:RxDownViaTXEN(0), bit1: TxPWDN(0), bit0:RxPWDN(0) 
				"000001111111000",
				-- Addr: 0x10, bit7:EnTxGain(0), bit6~4:G1(), bit3:(0), bit2~0:N(), 
				"001000010000010",
				-- Addr: 0x11, bit7:(0), bit6~4:G2(), bit3:(0), bit2~0:G3()
				"000000000000000",

				-- Addr: 0x06, bit76: CLK2DIV, bit5: CLK2Inv, bit4: CLK2Dis, bit32: CLK1DIV, bit1: CLK1Inv, bit0: CLK1Dis
				--"000011001000000",
				"000000000000000",
				-- Addr: 0x02, bit76: CLK2DIV, bit5: CLK2Inv, bit4: CLK2Dis, bit32: CLK1DIV, bit1: CLK1Inv, bit0: CLK1Dis
				"000000000000000",
				"000000000000000",
				"000000000000000",
				"000000000000000",
				"000000000000000",
				"000000000000000",
				"000000000000000",
				"000000000000000"
			);
	------------------------------------
	-- Signals: Monitoring through esp32 
	signal	esp_rdy_cur, esp_rdy_pre  : std_logic := '0';
	signal	esp_clk_cur, esp_clk_pre  : std_logic := '0';
	signal 	ESP_Data_out : std_logic_vector(7 downto 0):= (others => '0');
	-----------------------------------------------
----------------------
component DCM_Pre
port
 (-- Clock in ports
  CLK_OSC_IN           : in     std_logic;
  -- Clock out ports
  CLK_OUT_150M          : out    std_logic;
  -- Status and control signals
  CLK_VALID         : out    std_logic
 );
end component;
--------------------------
component DCM_Post
port
 (-- Clock in ports
  CLK_IN_75M   : in     std_logic;
  -- Clock out ports
  CLK_OUT_75M  : out    std_logic;
  CLK_OUT_150M : out    std_logic;
  CLK_OUT_5M   : out    std_logic;
  CLK_VALID    : out    std_logic
 );
end component;
-----------------------------
component ADSPI_DCM
port
 (-- Clock in ports
  CLK_IN_37_5	: in     std_logic;
  -- Clock out ports
  CLK_OUT_37_5  : out    std_logic;
  CLK_VALID     : out    std_logic
 );
end component;
-----------------------------
COMPONENT RAM_Block
  PORT (
    clka : IN STD_LOGIC;
    ena : IN STD_LOGIC;
    wea : IN STD_LOGIC_VECTOR(0 DOWNTO 0);
    addra : IN STD_LOGIC_VECTOR(9 DOWNTO 0);
    dina : IN STD_LOGIC_VECTOR(9 DOWNTO 0);
    clkb : IN STD_LOGIC;
    addrb : IN STD_LOGIC_VECTOR(9 DOWNTO 0);
    doutb : OUT STD_LOGIC_VECTOR(9 DOWNTO 0)
  );
END COMPONENT;
----------------------------------------------
----------------------------------------------
begin
	-------------------------------------------
	AD_SCLK <= not AD_SPI_cntr(0);
	AD_SDIO <= AD_SDIO_out when AD_SDIO_dir='1' else 'Z';
	AD_MODE	<= '0';
	AD_CNFG <= '0';
	AD_RST	<= AD_reset;
	AD_PGA	<= std_logic_vector(ADRxGain);
	-------------------------
	process(CLK_37M) 
	begin
		if rising_edge(CLK_37M)  then
			if (AD_res_flag	= '0') then
				AD_RST_cntr <= AD_RST_cntr + 1;
				if (AD_RST_cntr(23) = '1') then
					AD_SEN <= '1';
					AD_reset <= '1';
				end if;
				if (AD_RST_cntr(24) = '1') then
					AD_res_flag	<=	'1';
					AD_init <= '1';
					AD_SPI_cntr <= (others => '0');
					AD_RST_cntr <= (others => '0');
				end if;
			end if;

			if (AD_init = '1') then
				AD_SPI_cntr <= AD_SPI_cntr + 1;
				
				case AD_SPI_cntr is
				
				when "0000000" =>
					AD_SEN <= '0';
					AD_SPI_reg <= AD_Registers(to_integer(AD_reg_idx));
					AD_SDIO_out	<= '0'; -- Write
					AD_SDIO_dir <= '1'; -- set as output
					AD_Readback_flag <= '0';
				
				when "0100000" =>	--32
					AD_SEN <= '1';
				
				when "0100010" =>	-- 34
					AD_SEN <= '0';
					AD_SPI_reg <= AD_Registers(to_integer(AD_reg_idx));
					AD_SPI_comp <= AD_Registers(to_integer(AD_reg_idx));
					AD_SDIO_out	<= '1'; -- Read back
				
				when "0110010" =>	-- 50
					AD_SDIO_dir <= '0'; -- set as high-Z
					AD_SPI_ReadBack <= "00000000";
					AD_Readback_flag <= '1';
					AD_reg_idx <= AD_reg_idx + 1;
				
				when "1000010" => -- 66
					AD_SEN <= '1';
					AD_SPI_cntr <= (others => '0');
					if (AD_reg_idx = NumOfRegs) then
						AD_init <= '0';						
						--if(AD_SPI_ReadBack /= AD_Registers(to_integer(NumOfRegs)-1)(7 downto 0)) then
							--Sync_LED <= '1';
						--	AD_SPI_error <= '1';
						--end if;
					end if;
					if (AD_SPI_ReadBack = AD_SPI_comp(7 downto 0)) then
						AD_SPI_error <= '0';
					else
						AD_SPI_error <= '1';
					end if;
				when others =>
					if ((AD_SPI_cntr(0) = '0') and (AD_Readback_flag = '0')) then
						AD_SDIO_out	<= AD_SPI_reg(14);
						AD_SPI_reg	<= (AD_SPI_reg(13 downto 0) & '0');
					end if;
					if ((AD_SPI_cntr(0) = '1') and (AD_Readback_flag = '1')) then
						AD_SPI_ReadBack(7 downto 0) <= AD_SPI_ReadBack(6 downto 0) & AD_SDO;
					end if;
				end case;
			else
				AD_SEN <= '1';
				AD_SPI_cntr <= (others => '0');
				AD_reg_idx <= (others => '0');
			end if;
		end if;
	end process;
	-----------------------------------------------
	-----------------------------------------------
	Test_Rx_p <= Test_sig_Rx;
	Test_Rx_n <= (not Test_sig_Rx);
	process(CLK_150M)
	begin
		if rising_edge(CLK_150M) then
			test_sig_cntr <= test_sig_cntr + 1;
			if (test_sig_cntr = to_unsigned(8, 4)) then
				test_sig_cntr <= (others => '0');
				Test_sig_Rx <= not Test_sig_Rx;
			end if;
			if (AD_pwup = '0') then
				test_sig_cntr <= (others => '0');
				Test_sig_Rx <= '0';
			end if;
		end if;
	end process;
	----------------------------------------------------------------------
	------------------------------------------------------------------------
	----------------------------------------------------------------------
	AD_ADIO 	<= AD_Tx_Dat when AD_Tx_En='1' else (others=>'Z');
	AD_Tx_Dat 	<= (others => '0');
	AD_PWDN		<= not AD_pwup;
	AD_TXEN		<= AD_Tx_En;
	AD_RXEN		<= AD_Rx_En;
	ESP32_Data 	<= ESP_Data_out;
	--------------------------
	process(CLK_75M) --75 MHz from AD through DCM
	begin
		if rising_edge(CLK_75M)  then
			RAM1_WE	<= "0";
			---------------------------------------------
			----------------------------------------------------------
			-- Timing handler:
			Timer_cntr <= Timer_cntr + 1;
			if (Timer_cntr = to_unsigned(0, 16)) then
				AD_pwup	<= '1';
				AD_Tx_En  <= '0';
			end if;
			if (Timer_cntr = to_unsigned(1024, 16)) then
				Scan_En   <= '1';
				AD_Rx_En  <= '1';
				Ram_Waddr_cntr	<=	(others => '0');
			end if;
			------------------------------------------
			-- Fetching data out of AD9865:
			AD_Rx_Dat 	<= 	AD_ADIO;
			if (Scan_En = '1') then	
				RAM1_WData  <= 	AD_Rx_Dat;
				Ram_Waddr_cntr	<=	Ram_Waddr_cntr + 1;
				RAM1_WAddr	<=	std_logic_vector(Ram_Waddr_cntr);
				RAM1_WE   	<= "1";
				if (Ram_Waddr_cntr = to_unsigned(1023, 10)) then
					AD_pwup	<= '0';
					Scan_En   <= '0';
					AD_Rx_En  <= '0';
				end if;
			end if;
			-----------------------------------
			-- Monitoring: Interaction with ESP32 
			esp_rdy_cur	<=	ESP32_Ready;
			esp_rdy_pre	<=	esp_rdy_cur;
			esp_clk_cur	<=	ESP32_clk;
			esp_clk_pre	<=	esp_clk_cur;
			if ((esp_rdy_pre = '1') and (esp_clk_cur = '1') and (esp_clk_pre = '0')) then -- rising edge
				Ram_Raddr_cntr	<=	Ram_Raddr_cntr + 1;
				RAM1_RAddr	<=	std_logic_vector(Ram_Raddr_cntr);
				ESP_Data_out	<=	RAM1_RData(9 downto 2);
			end if;
			if ((esp_rdy_cur = '1') and (esp_rdy_pre = '0')) then -- rising edge
				Ram_Raddr_cntr <= (others => '0');
			end if;
		------------------------------------------------------------------------
		end if;
	end process;
---------------------------------
--------------------------------------------
Inst_Post_DCM : DCM_Post
  port map
   (-- Clock in ports
    CLK_IN_75M		=> 	AD_CLK1,
    -- Clock out ports
    CLK_OUT_75M 	=> 	CLK_75M,
    CLK_OUT_150M 	=> 	CLK_150M,
	CLK_OUT_5M		=>	CLK_5M,
	-- Status and control signals
    CLK_VALID 		=> open
	);
------------------------------
inst_Pre_DCM : DCM_Pre
  port map
   (-- Clock in ports
    CLK_OSC_IN => CLK_IN,
    -- Clock out ports
    CLK_OUT_150M => CLK_Pre_150M,
    -- Status and control signals
    CLK_VALID => open
	);
--------------------------------------
inst_ADSPI_DCM : ADSPI_DCM
  port map
   (-- Clock in ports
    CLK_IN_37_5 => AD_CLK2,
    -- Clock out ports
    CLK_OUT_37_5 => CLK_37M,
    CLK_VALID => open
	);
--------------------------------------
----------------------------------------
inst_RAM_block1 : RAM_Block
  PORT MAP (
    clka => CLK_75M,
    ena => '1',
    wea => RAM1_WE,
    addra => RAM1_WAddr,
    dina => RAM1_WData,
    clkb => CLK_75M,
    addrb => RAM1_RAddr,
    doutb => RAM1_RData
  );
-----------------------------------------
---------------------------------------
 AD_CLK_OUT	<=	AD_clk_synth;
process	(CLK_Pre_150M) 
begin	
	if rising_edge(CLK_Pre_150M) then
		AD_clk_synth <= not AD_clk_synth;
	end if;
end process;
--------------------------------------
--------------------------------------
end Behavioral;

