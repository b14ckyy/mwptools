
namespace ReadSB {
	[Compact]
	[CCode (cheader_filename = "decode_readsb.h", cname="readsb_pb_t", has_type_id = false)]
	public struct Pbuf {
		uint32 addr;
		int32 alt;
		uint32 hdg;
		uint32 speed;
		uint32 seen_pos;
		uint32 srange;
		double lat;
		double lon;
		uint8 catx;
		uint8 name[9];
		uint64 seen_tm;
	}
	[CCode (cheader_filename = "decode_readsb.h", cname = "decode_ac_pb")]
	public int decode_ac_pb(uint8[]input_array, out ReadSB.Pbuf[] output_array);

	[CCode (cheader_filename = "decode_readsb.h")]
	public const uint32 DISTNDEF;
}