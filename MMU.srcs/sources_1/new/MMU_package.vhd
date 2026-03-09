library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

package MMU_package is
     constant ADDR_W   : natural := 8; -- processor byte address
     constant BUS_A_W  : natural := 6; -- line address (addr[7:2])
     constant DATA_W   : natural := 32; -- 1 line = 32b (4 bytes)
     constant TAG_W    : natural := 4;  -- addr[7:4]
     constant IDX_W    : natural := 2;  -- addr[3:2] => 4 lines
     constant OFF_W    : natural := 2;  -- addr[1:0]
     
     type msi_state_t is (MSI_I, MSI_S, MSI_M);
     
     type bus_cmd_t is (BUS_NONE, BUS_RD, BUS_RDX, BUS_WB);
     
      subtype msi_enc_t is std_logic_vector(1 downto 0);

      function to_slv(s : msi_state_t) return msi_enc_t;
end package;


package body MMU_package is
    function to_slv(s : msi_state_t) return msi_enc_t is
    begin
        case s is
            when MSI_I => return "00";
            when MSI_S => return "01";
            when MSI_M => return "10";
            when others => return "00";
        end case;
    end function;
end package body; 