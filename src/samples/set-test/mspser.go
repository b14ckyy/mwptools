package main

import (
	"fmt"
	"go.bug.st/serial"
	"log"
	"os"
	"strings"
	"encoding/binary"
	"time"
)

const (
	msp_REBOOT             = 68
	msp_EEPROM_WRITE       = 250
	msp_COMMON_SETTING     = 0x1003
	msp_COMMON_SET_SETTING = 0x1004
)

const (
	state_INIT = iota
	state_M
	state_DIRN
	state_LEN
	state_CMD
	state_DATA
	state_CRC

	state_X_HEADER2
	state_X_FLAGS
	state_X_ID1
	state_X_ID2
	state_X_LEN1
	state_X_LEN2
	state_X_DATA
	state_X_CHECKSUM
)

const SETTING_STR string = "nav_rth_home_altitude"

func crc8_dvb_s2(crc byte, a byte) byte {
	crc ^= a
	for i := 0; i < 8; i++ {
		if (crc & 0x80) != 0 {
			crc = (crc << 1) ^ 0xd5
		} else {
			crc = crc << 1
		}
	}
	return crc
}

func msp_reader(p serial.Port, c0 chan SChan) {
	inp := make([]byte, 128)
	var count = uint16(0)
	var crc = byte(0)
	var sc SChan

	n := state_INIT
	for {
		nb, err := p.Read(inp)
		if err == nil && nb > 0 {
			for i := 0; i < nb; i++ {
				switch n {
				case state_INIT:
					if inp[i] == '$' {
						n = state_M
						sc.ok = false
						sc.len = 0
						sc.cmd = 0
					}
				case state_M:
					if inp[i] == 'M' {
						n = state_DIRN
					} else if inp[i] == 'X' {
						n = state_X_HEADER2
					} else {
						n = state_INIT
					}
				case state_DIRN:
					if inp[i] == '!' {
						n = state_LEN
					} else if inp[i] == '>' {
						n = state_LEN
						sc.ok = true
					} else {
						n = state_INIT
					}

				case state_X_HEADER2:
					if inp[i] == '!' {
						n = state_X_FLAGS
					} else if inp[i] == '>' {
						n = state_X_FLAGS
						sc.ok = true
					} else {
						n = state_INIT
					}

				case state_X_FLAGS:
					crc = crc8_dvb_s2(0, inp[i])
					n = state_X_ID1

				case state_X_ID1:
					crc = crc8_dvb_s2(crc, inp[i])
					sc.cmd = uint16(inp[i])
					n = state_X_ID2

				case state_X_ID2:
					crc = crc8_dvb_s2(crc, inp[i])
					sc.cmd |= (uint16(inp[i]) << 8)
					n = state_X_LEN1

				case state_X_LEN1:
					crc = crc8_dvb_s2(crc, inp[i])
					sc.len = uint16(inp[i])
					n = state_X_LEN2

				case state_X_LEN2:
					crc = crc8_dvb_s2(crc, inp[i])
					sc.len |= (uint16(inp[i]) << 8)
					if sc.len > 0 {
						n = state_X_DATA
						count = 0
						sc.data = make([]byte, sc.len)
					} else {
						n = state_X_CHECKSUM
					}
				case state_X_DATA:
					crc = crc8_dvb_s2(crc, inp[i])
					sc.data[count] = inp[i]
					count++
					if count == sc.len {
						n = state_X_CHECKSUM
					}

				case state_X_CHECKSUM:
					ccrc := inp[i]
					if crc != ccrc {
						fmt.Fprintf(os.Stderr, "CRC error on %d\n", sc.cmd)
					} else {
						c0 <- sc
					}
					n = state_INIT

				case state_LEN:
					sc.len = uint16(inp[i])
					crc = inp[i]
					n = state_CMD
				case state_CMD:
					sc.cmd = uint16(inp[i])
					crc ^= inp[i]
					if sc.len == 0 {
						n = state_CRC
					} else {
						sc.data = make([]byte, sc.len)
						n = state_DATA
						count = 0
					}
				case state_DATA:
					sc.data[count] = inp[i]
					crc ^= inp[i]
					count++
					if count == sc.len {
						n = state_CRC
					}
				case state_CRC:
					ccrc := inp[i]
					if crc != ccrc {
						fmt.Fprintf(os.Stderr, "CRC error on %d\n", sc.cmd)
					} else {
						c0 <- sc
					}
					n = state_INIT
				}
			}
		} else {
			if err != nil {
				fmt.Fprintf(os.Stderr, "Read error: %s\n", err)
			}
			p.Close()
			return
		}
	}
}

func encode_msp(cmd byte, payload []byte) []byte {
	var paylen byte
	if len(payload) > 0 {
		paylen = byte(len(payload))
	}
	buf := make([]byte, 6+paylen)
	buf[0] = '$'
	buf[1] = 'M'
	buf[2] = '<'
	buf[3] = paylen
	buf[4] = cmd
	if paylen > 0 {
		copy(buf[5:], payload)
	}
	crc := byte(0)
	for _, b := range buf[3:] {
		crc ^= b
	}
	buf[5+paylen] = crc
	return buf
}

func encode_msp2(cmd uint16, payload []byte) []byte {
	var paylen int16
	if len(payload) > 0 {
		paylen = int16(len(payload))
	}
	buf := make([]byte, 9+paylen)
	buf[0] = '$'
	buf[1] = 'X'
	buf[2] = '<'
	buf[3] = 0 // flags
	binary.LittleEndian.PutUint16(buf[4:6], cmd)
	binary.LittleEndian.PutUint16(buf[6:8], uint16(paylen))
	if paylen > 0 {
		copy(buf[8:], payload)
	}
	crc := byte(0)
	for _, b := range buf[3 : paylen+8] {
		crc = crc8_dvb_s2(crc, b)
	}
	buf[8+paylen] = crc
	return buf
}

func MSPSend(p serial.Port, cmd uint16, payload []byte) {
	rb := encode_msp2(cmd, payload)
	p.Write(rb)
}

func MSPSetting(p serial.Port) {
	lstr := len(SETTING_STR)
	buf := make([]byte, lstr+1)
	copy(buf, SETTING_STR)
	buf[lstr] = 0
	MSPSend(p, msp_COMMON_SETTING, buf)
}

func MSPEncodeSetting(p serial.Port, val uint16) {
	lstr := len(SETTING_STR)
	buf := make([]byte, lstr+3)
	copy(buf, SETTING_STR)
	buf[lstr] = 0
	binary.LittleEndian.PutUint16(buf[lstr+1:lstr+3], val)
	MSPSend(p, msp_COMMON_SET_SETTING, buf)
}

func MSPReboot(p serial.Port) {
	rb := encode_msp(msp_REBOOT, nil)
	p.Write(rb)
}

func MSPSave(p serial.Port) {
	rb := encode_msp2(msp_EEPROM_WRITE, nil)
	p.Write(rb)
}

func Decode_buffer(buf []byte) uint16 {
	uval := binary.LittleEndian.Uint16(buf[0:2])
	return uval
}

func MSPRunner(name string, c0 chan SChan, init bool) serial.Port {
	mode := &serial.Mode{
		BaudRate: 115200,
	}
	var sb strings.Builder
	sb.WriteString("/dev/")
	sb.WriteString(name)

	p, err := serial.Open(sb.String(), mode)

	if err != nil {
		log.Fatal(err)
	}
	go msp_reader(p, c0)
	// drain the serial first time around
	if !init {
		for done := false; !done; {
			select {
			case <-c0:
			case <-time.After(1 * time.Second):
				done = true
			}
		}
	}
	return p
}

func MSPClose(p serial.Port) {
	p.Close()
}
